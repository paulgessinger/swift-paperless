//
//  SingleFlightTests.swift
//  Common
//

import Foundation
import Testing

@testable import Common

/// Collects values reported to a caller's progress handler, in order.
private final class Recorder: @unchecked Sendable {
  private let lock = NSLock()
  private var _values: [Double] = []
  var values: [Double] { lock.withLock { _values } }
  var handler: @Sendable (Double) -> Void {
    { value in self.lock.withLock { self._values.append(value) } }
  }
}

/// A producer the test drives by hand: it parks until `release()` is called,
/// so callers can be lined up on the same flight deterministically.
private actor Gate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    isOpen = true
    for waiter in waiters { waiter.resume() }
    waiters = []
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var _value = 0
  var value: Int { lock.withLock { _value } }
  func bump() { lock.withLock { _value += 1 } }
}

/// Keeps the fan-out handler alive past the operation's return, so a test can
/// report into a flight that has already completed.
private final class HandlerBox: @unchecked Sendable {
  private let lock = NSLock()
  private var _handler: (@Sendable (Double) -> Void)?
  var handler: (@Sendable (Double) -> Void)? { lock.withLock { _handler } }
  func set(_ handler: @escaping @Sendable (Double) -> Void) {
    lock.withLock { _handler = handler }
  }
}

private struct TestError: Error {}

@Suite
struct SingleFlightTests {
  /// Polls instead of sleeping a fixed amount: the callers we wait for are
  /// scheduled on other executors, and a fixed sleep is either flaky or slow.
  private func waitUntil(
    _ condition: @Sendable () -> Bool,
    timeout: Duration = .seconds(5),
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
      if ContinuousClock.now > deadline {
        Issue.record(comment ?? "timed out waiting for condition", sourceLocation: sourceLocation)
        return
      }
      try await Task.sleep(for: .milliseconds(2))
    }
  }

  @Test
  func concurrentCallersShareOneOperation() async throws {
    let flight = SingleFlight<String, Int>()
    let gate = Gate()
    let runs = Counter()
    let a = Recorder()
    let b = Recorder()

    let first = Task {
      try await flight.run(key: "k", progress: a.handler) { _ in
        runs.bump()
        await gate.wait()
        return 42
      }
    }
    try await waitUntil { flight.subscriberCount(forKey: "k") == 1 }

    let second = Task {
      try await flight.run(key: "k", progress: b.handler) { _ in
        runs.bump()
        return -1
      }
    }
    try await waitUntil { flight.subscriberCount(forKey: "k") == 2 }

    await gate.release()
    #expect(try await first.value == 42)
    #expect(try await second.value == 42)
    #expect(runs.value == 1)
  }

  @Test
  func everyJoinedCallerReceivesProgress() async throws {
    let flight = SingleFlight<String, Int>()
    let gate = Gate()
    let a = Recorder()
    let b = Recorder()

    let first = Task {
      try await flight.run(key: "k", progress: a.handler) { report in
        report(0.1)
        await gate.wait()
        report(0.5)
        report(1.0)
        return 7
      }
    }
    // The first caller is attached as soon as `run` returns from the lock, and
    // 0.1 is reported before the gate parks the operation.
    try await waitUntil { a.values == [0.1] }

    let second = Task {
      try await flight.run(key: "k", progress: b.handler) { _ in -1 }
    }
    try await waitUntil { flight.subscriberCount(forKey: "k") == 2 }

    await gate.release()
    #expect(try await first.value == 7)
    #expect(try await second.value == 7)

    #expect(a.values == [0.1, 0.5, 1.0])
    // The joiner missed nothing after joining, and got the last value replayed
    // so its bar starts where the download actually is.
    #expect(b.values == [0.1, 0.5, 1.0])
  }

  @Test
  func cancellingOneCallerLeavesTheOthersIntact() async throws {
    let flight = SingleFlight<String, Int>()
    let gate = Gate()
    let a = Recorder()
    let b = Recorder()
    let operationCancelled = Counter()

    let first = Task {
      try await flight.run(key: "k", progress: a.handler) { report in
        await gate.wait()
        if Task.isCancelled { operationCancelled.bump() }
        report(0.5)
        report(1.0)
        return 7
      }
    }
    try await waitUntil { flight.subscriberCount(forKey: "k") == 1 }

    let second = Task {
      try await flight.run(key: "k", progress: b.handler) { _ in -1 }
    }
    try await waitUntil { flight.subscriberCount(forKey: "k") == 2 }

    second.cancel()
    try await waitUntil { flight.subscriberCount(forKey: "k") == 1 }

    await gate.release()
    #expect(try await first.value == 7)

    // Only the cancelled caller's subscription went away: the shared operation
    // ran to completion and the surviving caller saw all of it.
    #expect(a.values == [0.5, 1.0])
    #expect(b.values.isEmpty)
    #expect(operationCancelled.value == 0)
    // Documented semantics: a cancelled caller stops being told about progress
    // but still receives the shared result.
    #expect(try await second.value == 7)
  }

  @Test
  func completionClearsAllSubscriptions() async throws {
    let flight = SingleFlight<String, Int>()
    let box = HandlerBox()
    let a = Recorder()

    let value = try await flight.run(key: "k", progress: a.handler) { report in
      box.set(report)
      report(0.5)
      return 7
    }
    #expect(value == 7)
    #expect(flight.subscriberCount(forKey: "k") == 0)

    // A late report from the finished operation reaches nobody.
    box.handler?(0.9)
    #expect(a.values == [0.5])
  }

  @Test
  func failureClearsAllSubscriptionsAndReachesEveryCaller() async throws {
    let flight = SingleFlight<String, Int>()
    let gate = Gate()
    let box = HandlerBox()
    let a = Recorder()
    let b = Recorder()

    let first = Task {
      try await flight.run(key: "k", progress: a.handler) { report in
        box.set(report)
        await gate.wait()
        throw TestError()
      }
    }
    try await waitUntil { flight.subscriberCount(forKey: "k") == 1 }

    let second = Task {
      try await flight.run(key: "k", progress: b.handler) { _ in -1 }
    }
    try await waitUntil { flight.subscriberCount(forKey: "k") == 2 }

    await gate.release()
    await #expect(throws: TestError.self) { try await first.value }
    await #expect(throws: TestError.self) { try await second.value }

    #expect(flight.subscriberCount(forKey: "k") == 0)
    box.handler?(0.9)
    #expect(a.values.isEmpty)
    #expect(b.values.isEmpty)
  }

  @Test
  func failedFlightDoesNotPoisonTheKey() async throws {
    let flight = SingleFlight<String, Int>()
    let runs = Counter()

    await #expect(throws: TestError.self) {
      try await flight.run(key: "k") { _ in
        runs.bump()
        throw TestError()
      }
    }
    let value = try await flight.run(key: "k") { _ in
      runs.bump()
      return 7
    }

    #expect(value == 7)
    #expect(runs.value == 2)
  }

  @Test
  func differentKeysDoNotShare() async throws {
    let flight = SingleFlight<String, Int>()
    let gate = Gate()
    let runs = Counter()

    let first = Task {
      try await flight.run(key: "a") { _ in
        runs.bump()
        await gate.wait()
        return 1
      }
    }
    let second = Task {
      try await flight.run(key: "b") { _ in
        runs.bump()
        await gate.wait()
        return 2
      }
    }
    try await waitUntil { runs.value == 2 }

    await gate.release()
    #expect(try await first.value == 1)
    #expect(try await second.value == 2)
  }
}
