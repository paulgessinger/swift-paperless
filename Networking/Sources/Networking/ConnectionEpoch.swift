//
//  ConnectionEpoch.swift
//  Networking
//
//  A VPN tunnel coming up doesn't change whether the device is online, but it
//  does strand connections: an attempt already in flight stays on the route it
//  started on, and a pooled connection may no longer lead anywhere. This counts
//  those events, so requests can drop what predates them.
//

import Foundation
import os

/// Counts the events that may have invalidated a session's connections: a
/// changed network route, or a long stay in the background.
public final class ConnectionEpoch: Sendable {
  /// Fed by `NetworkMonitor` (in AppShared). Where no monitor runs, such as the
  /// share extension, it never moves and requests behave as if it didn't exist.
  public static let shared = ConnectionEpoch()

  private struct State {
    var route: [String]?
    var value: UInt64 = 0
    var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    mutating func advance() -> [CheckedContinuation<Void, Never>] {
      value += 1
      defer { waiters = [:] }
      return Array(waiters.values)
    }
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  public init() {}

  public var value: UInt64 {
    state.withLock { $0.value }
  }

  /// Record the current route, as a value that differs when the route does.
  /// The first report only sets the baseline: nothing predates it.
  public func update(route: [String]) {
    let waiters = state.withLock { state in
      defer { state.route = route }
      guard let previous = state.route, previous != route else {
        return [CheckedContinuation<Void, Never>]()
      }
      return state.advance()
    }
    waiters.forEach { $0.resume() }
  }

  /// Advance without a route change.
  public func invalidate() {
    state.withLock { $0.advance() }.forEach { $0.resume() }
  }

  /// Returns once the epoch differs from `epoch`, or the task is cancelled.
  private func waitForChange(from epoch: UInt64) async {
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let isDone = state.withLock { state in
          // Checked under the lock: `onCancel` running first has already set
          // the flag, and running later finds the waiter to resume.
          if Task.isCancelled || state.value != epoch { return true }
          state.waiters[id] = continuation
          return false
        }
        if isDone { continuation.resume() }
      }
    } onCancel: {
      state.withLock { $0.waiters.removeValue(forKey: id) }?.resume()
    }
  }

  /// Run `operation`, cancelling it if the epoch moves on from `epoch`.
  ///
  /// - Throws: ``ConnectionEpochChanged`` if the epoch moved first, otherwise
  ///   what `operation` throws. A cancelled caller gets `CancellationError`.
  func cancellingOnChange<T: Sendable>(
    from epoch: UInt64, _ operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T?.self) { group in
      defer { group.cancelAll() }
      group.addTask { try await operation() }
      group.addTask {
        await self.waitForChange(from: epoch)
        return nil
      }
      if let result = try await group.next(), let result { return result }
      try Task.checkCancellation()
      throw ConnectionEpochChanged()
    }
  }
}

/// A request was abandoned because the connection epoch moved on.
struct ConnectionEpochChanged: Error {}

/// A session's connection pool, flushed once per ``ConnectionEpoch``.
final class SessionConnections: Sendable {
  let session: URLSession
  let epoch: ConnectionEpoch
  private let flushedEpoch: OSAllocatedUnfairLock<UInt64>

  init(session: URLSession, epoch: ConnectionEpoch) {
    self.session = session
    self.epoch = epoch
    flushedEpoch = OSAllocatedUnfairLock(initialState: epoch.value)
  }

  /// Make requests from here on open new connections if the epoch moved since
  /// the last flush. Requests in flight are unaffected.
  func refresh() async {
    let current = epoch.value
    let isStale = flushedEpoch.withLock { flushed in
      defer { flushed = current }
      return flushed != current
    }
    guard isStale else { return }
    Logger.networking.notice("Flushing connections left from an earlier network path")
    await session.flush()
  }
}
