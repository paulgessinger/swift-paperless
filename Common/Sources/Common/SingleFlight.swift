//
//  SingleFlight.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.09.26.
//

import Foundation
import os

/// Keyed single-flight execution with progress fan-out.
///
/// Callers asking for the same `key` while work is in flight share one
/// operation instead of racing. Unlike a plain `[Key: Task]` map, the shared
/// operation reports progress to *every* joined caller, so a caller that
/// arrives second still drives its own progress UI instead of watching a bar
/// sit at zero until the download it joined happens to finish.
///
/// Cancellation is deliberately per-caller and affects progress delivery only:
/// a cancelled caller stops receiving progress immediately, but the shared
/// operation keeps running — for the other callers, and even when the last one
/// leaves. That is the pre-existing behaviour of the download path this backs
/// (an unstructured `Task` never inherited the caller's cancellation), and it
/// is what we want: the operation is what populates the shared on-disk content
/// cache, so finishing it serves whoever asks next, while tearing it down
/// under the remaining callers would fail requests nobody cancelled.
public final class SingleFlight<Key: Hashable & Sendable, Value: Sendable>: Sendable {
  public typealias ProgressHandler = @Sendable (Double) -> Void

  private struct Entry {
    let id: Int
    let task: Task<Value, Error>
    var subscribers: [Int: ProgressHandler] = [:]
    /// Replayed to late joiners. Progress arrives in bursts, so without it a
    /// caller joining between two ticks renders an empty bar until the next
    /// one — which for a nearly-finished download can be never.
    var lastProgress: Double?
  }

  private struct State {
    var entries: [Key: Entry] = [:]
    /// Shared counter for both entry and subscriber identity: subscriber
    /// tickets have to stay unique across entries so that unsubscribing a
    /// stale ticket can never unsubscribe someone else.
    var nextID = 0
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  public init() {}

  /// Runs `operation` for `key`, or joins the one already in flight.
  ///
  /// `progress` receives every value the shared operation reports from the
  /// moment this call joins until it returns (or is cancelled). `operation` is
  /// only invoked when there is nothing in flight for `key`; it is handed the
  /// fan-out handler to report through.
  public func run(
    key: Key,
    progress: ProgressHandler? = nil,
    operation: @escaping @Sendable (@escaping ProgressHandler) async throws -> Value
  ) async throws -> Value {
    let (ticket, task, replay) = state.withLock {
      state -> (Int, Task<Value, Error>, Double?) in
      let ticket = state.nextID
      state.nextID += 1

      if var entry = state.entries[key] {
        entry.subscribers[ticket] = progress
        let replay = entry.lastProgress
        state.entries[key] = entry
        return (ticket, entry.task, replay)
      }

      let entryID = state.nextID
      state.nextID += 1
      let report = makeReporter(key: key, entryID: entryID)
      // Started while holding the lock so a concurrent caller can't miss the
      // entry and start a second flight. The task body only ever takes the
      // lock from its own executor, so this can't deadlock.
      let task = Task<Value, Error> { [self] in
        defer { finish(key: key, entryID: entryID) }
        return try await operation(report)
      }
      var entry = Entry(id: entryID, task: task)
      entry.subscribers[ticket] = progress
      state.entries[key] = entry
      return (ticket, task, nil)
    }

    // Outside the lock: subscriber handlers are caller code and must never run
    // under it.
    if let replay, let progress {
      progress(replay)
    }

    return try await withTaskCancellationHandler {
      defer { unsubscribe(key: key, ticket: ticket) }
      return try await task.value
    } onCancel: {
      unsubscribe(key: key, ticket: ticket)
    }
  }

  private func makeReporter(key: Key, entryID: Int) -> ProgressHandler {
    { [state] value in
      let handlers = state.withLock { state -> [ProgressHandler] in
        // The entry id guards against a later flight for the same key: a
        // straggling report from a finished operation must not resurrect a
        // stale `lastProgress` on top of the new one.
        guard var entry = state.entries[key], entry.id == entryID else { return [] }
        entry.lastProgress = value
        state.entries[key] = entry
        return Array(entry.subscribers.values)
      }
      for handler in handlers {
        handler(value)
      }
    }
  }

  /// Drops the entry on success *and* failure, so neither outcome leaves
  /// subscriptions behind and the next caller starts a fresh flight.
  private func finish(key: Key, entryID: Int) {
    state.withLock { state in
      guard state.entries[key]?.id == entryID else { return }
      state.entries[key] = nil
    }
  }

  private func unsubscribe(key: Key, ticket: Int) {
    state.withLock { state in
      state.entries[key]?.subscribers[ticket] = nil
    }
  }

  /// Test hook: number of callers currently attached to `key`'s flight.
  func subscriberCount(forKey key: Key) -> Int {
    state.withLock { $0.entries[key]?.subscribers.count ?? 0 }
  }
}
