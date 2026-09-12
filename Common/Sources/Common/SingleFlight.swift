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

  private struct Subscriber {
    let handler: ProgressHandler
    /// Sequence number of the newest value this subscriber has been handed —
    /// delivered or queued. It only ever moves forward, which is what stops a
    /// late replay from stepping on a newer live report that overtook it.
    var deliveredSeq = 0
    /// Newest value waiting for `handler`, if any. Only the task owning the
    /// delivery loop drains it, and it holds at most one value: progress is a
    /// level, not an event, so coalescing a burst is a feature.
    var pending: Double?
    /// True while some task is inside `handler`. Whoever sets it owns delivery
    /// until nothing is pending, so a caller's handler is never re-entered and
    /// never runs on two threads at once.
    var isDelivering = false
  }

  private struct Entry {
    let id: Int
    let task: Task<Value, Error>
    var subscribers: [Int: Subscriber] = [:]
    /// Replayed to late joiners. Progress arrives in bursts, so without it a
    /// caller joining between two ticks renders an empty bar until the next
    /// one — which for a nearly-finished download can be never.
    var lastProgress: Double?
    /// Counts reports for this flight. A joiner's replay carries the number
    /// `lastProgress` was recorded under, so the delivery path can tell a stale
    /// replay from a live report that beat it there, and drop it.
    var progressSeq = 0
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
      state -> (Int, Task<Value, Error>, (seq: Int, value: Double)?) in
      let ticket = state.nextID
      state.nextID += 1

      if var entry = state.entries[key] {
        // A caller without a handler is not a subscriber at all — it only wants
        // the shared result.
        if let progress { entry.subscribers[ticket] = Subscriber(handler: progress) }
        let replay = entry.lastProgress.map { (seq: entry.progressSeq, value: $0) }
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
      if let progress { entry.subscribers[ticket] = Subscriber(handler: progress) }
      state.entries[key] = entry
      return (ticket, task, nil)
    }

    // Outside the lock: subscriber handlers are caller code and must never run
    // under it. That gap is exactly the hazard — a report landing between the
    // registration above and this line reaches the new subscriber first — so
    // the replay takes the same per-subscriber path as a live report, where
    // being older than what already arrived makes it a no-op.
    if let replay {
      deliver(key: key, ticket: ticket, seq: replay.seq, value: replay.value)
    }

    return try await withTaskCancellationHandler {
      defer { unsubscribe(key: key, ticket: ticket) }
      return try await task.value
    } onCancel: {
      unsubscribe(key: key, ticket: ticket)
    }
  }

  private func makeReporter(key: Key, entryID: Int) -> ProgressHandler {
    // Capturing `self` adds no retain cycle the entry does not already have:
    // the in-flight task retains `self` too, and `finish` drops both.
    { [self] value in
      let fanout = state.withLock { state -> (seq: Int, tickets: [Int])? in
        // The entry id guards against a later flight for the same key: a
        // straggling report from a finished operation must not resurrect a
        // stale `lastProgress` on top of the new one.
        guard var entry = state.entries[key], entry.id == entryID else { return nil }
        entry.progressSeq += 1
        entry.lastProgress = value
        state.entries[key] = entry
        return (entry.progressSeq, Array(entry.subscribers.keys))
      }
      guard let fanout else { return }
      for ticket in fanout.tickets {
        deliver(key: key, ticket: ticket, seq: fanout.seq, value: value)
      }
    }
  }

  /// Hands `value` to one subscriber, in sequence order, one value at a time.
  ///
  /// Handlers are caller code and cannot run under the lock, so registering a
  /// late joiner and replaying to it cannot be one atomic step: a live report
  /// can — and does — overtake the replay. Ordering is restored here instead.
  /// Every value carries the sequence number of the report it came from, a
  /// subscriber only ever moves forward in that sequence, and the first task to
  /// find the subscriber idle owns its delivery loop until nothing is pending.
  /// So a handler is never re-entered, never runs on two threads at once, and
  /// never sees progress go backwards — the stale value is dropped, not
  /// delivered late.
  private func deliver(key: Key, ticket: Int, seq: Int, value: Double) {
    let handler: ProgressHandler? = state.withLock { state -> ProgressHandler? in
      guard var entry = state.entries[key], var subscriber = entry.subscribers[ticket] else {
        return nil
      }
      // Something at least as new was already handed over: this value is stale.
      guard seq > subscriber.deliveredSeq else { return nil }
      subscriber.deliveredSeq = seq
      subscriber.pending = value
      let alreadyDelivering = subscriber.isDelivering
      if !alreadyDelivering { subscriber.isDelivering = true }
      entry.subscribers[ticket] = subscriber
      state.entries[key] = entry
      // Someone else owns the loop; they will pick this up.
      return alreadyDelivering ? nil : subscriber.handler
    }
    guard let handler else { return }

    while true {
      let next: Double? = state.withLock { state -> Double? in
        guard var entry = state.entries[key], var subscriber = entry.subscribers[ticket] else {
          // Unsubscribed, or the flight finished: stop. There is no state left
          // to hand ownership back to, and a cancelled caller wants no more.
          return nil
        }
        let pending = subscriber.pending
        subscriber.pending = nil
        if pending == nil { subscriber.isDelivering = false }
        entry.subscribers[ticket] = subscriber
        state.entries[key] = entry
        return pending
      }
      guard let next else { return }
      handler(next)
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
