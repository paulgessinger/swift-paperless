//
//  KeyOwnershipTests.swift
//  Common
//

import Foundation
import Testing

@testable import Common

/// Parks callers until `release()`. Cancellation does not unpark them, which is
/// how a test models a writer that only notices cancellation between steps.
private actor Latch {
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

/// Records steps from any isolation, in order.
private final class Log: @unchecked Sendable {
  private let lock = NSLock()
  private var _entries: [String] = []
  var entries: [String] { lock.withLock { _entries } }
  func append(_ entry: String) { lock.withLock { _entries.append(entry) } }
}

private struct WriteFailed: Error {}

@MainActor
private func waitUntil(
  _ condition: () -> Bool,
  _ comment: Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation
) async throws {
  let deadline = ContinuousClock.now + .seconds(5)
  while !condition() {
    if ContinuousClock.now > deadline {
      Issue.record(comment ?? "timed out waiting for condition", sourceLocation: sourceLocation)
      return
    }
    try await Task.sleep(for: .milliseconds(2))
  }
}

@MainActor
@Suite
struct KeyOwnershipTests {
  @Test("Release only clears the key when the given owner still holds it")
  func releaseOnlyOwnOwner() async {
    let ownership = KeyOwnership<String>()
    let first = KeyOwnership<String>.Owner {}
    let second = KeyOwnership<String>.Owner {}

    ownership.claim("a", by: first)
    #expect(ownership.isOwned("a"))
    #expect(!ownership.isOwned("b"))

    // A newer writer replaced `first`; `first` finishing must not unprotect it.
    ownership.claim("a", by: second)
    ownership.release("a", ifOwnedBy: first)
    #expect(ownership.isOwned("a"))

    ownership.release("a", ifOwnedBy: second)
    #expect(!ownership.isOwned("a"))
  }

  @Test("Draining cancels the owner and returns only once it has actually stopped")
  func drainWaitsForOwnerToStop() async throws {
    let ownership = KeyOwnership<String>()
    let latch = Latch()
    let log = Log()

    // A writer that notices cancellation at its next checkpoint, but has to
    // finish the step it is in first — like a fill mid-page.
    let owner = KeyOwnership<String>.Owner {
      await latch.wait()
      log.append("step finished")
      try Task.checkCancellation()
      log.append("next step")
    }
    ownership.claim("key", by: owner)

    let drainer = Task { @MainActor in
      await ownership.drain("key")
      log.append("drained")
    }
    try await Task.sleep(for: .milliseconds(20))
    #expect(log.entries.isEmpty, "drain must not return while the owner is mid-step")
    #expect(ownership.isOwned("key"))

    await latch.release()
    await drainer.value
    #expect(log.entries == ["step finished", "drained"])
    #expect(!ownership.isOwned("key"))
  }

  @Test("Draining an unowned key returns immediately")
  func drainUnowned() async {
    let ownership = KeyOwnership<String>()
    await ownership.drain("nothing")
    #expect(!ownership.isOwned("nothing"))
  }

  @Test("After a drain, the drainer's own claim is not released by the drained owner")
  func drainedOwnerDoesNotReleaseSuccessor() async throws {
    // The fill hand-over: the departing fill's registration retracts only its own
    // entry, so the fill that drained it stays the key's writer.
    let ownership = KeyOwnership<String>()
    let latch = Latch()
    let old = KeyOwnership<String>.Owner {
      await latch.wait()
      try Task.checkCancellation()
    }
    ownership.claim("key", by: old)
    let drain = Task { @MainActor in await ownership.drain("key") }
    // Let the other main-actor task reach its `await` before going on.
    try await Task.sleep(for: .milliseconds(20))
    await latch.release()
    await drain.value

    let successor = KeyOwnership<String>.Owner { try await Task.sleep(for: .seconds(60)) }
    ownership.claim("key", by: successor)
    ownership.release("key", ifOwnedBy: old)
    #expect(ownership.isOwned("key"))
    successor.cancel()
  }

  @Test(
    "Two drainers of one owner cannot both end up claiming the key",
    .bug(id: "735"))
  func concurrentDrainersDoNotBothClaim() async throws {
    // Two fills for one key arrive while a third owns it. Both wait in `drain`
    // on that same owner; when it stops, the first resumes and claims. The
    // second must not then claim over the first without stopping it — that
    // leaves two fills writing one key's `query_order`.
    let ownership = KeyOwnership<String>()
    let latch = Latch()
    let old = KeyOwnership<String>.Owner {
      await latch.wait()
      try Task.checkCancellation()
    }
    ownership.claim("key", by: old)

    @MainActor func drainThenClaim() async -> KeyOwnership<String>.Owner {
      await ownership.drain("key")
      // No suspension between `drain` returning and the claim, as in `fillQuery`.
      let fill = KeyOwnership<String>.Owner { try await Task.sleep(for: .seconds(60)) }
      ownership.claim("key", by: fill)
      return fill
    }
    let first = Task { @MainActor in await drainThenClaim() }
    let second = Task { @MainActor in await drainThenClaim() }
    // Let both drainers reach their `await` on `old` before it stops.
    try await Task.sleep(for: .milliseconds(20))
    await latch.release()
    let fills = [await first.value, await second.value]

    let holder = try #require(ownership.owner(of: "key"))
    #expect(fills.contains(holder))
    for fill in fills where fill != holder {
      #expect(fill.isCancelled, "a replaced claimant must have been stopped, not left writing")
    }
    for fill in fills { fill.cancel() }
  }

  @Test("Taking a key over drains its owner and registers the new one", .bug(id: "735"))
  func takeOverReplacesOwner() async throws {
    let ownership = KeyOwnership<String>()
    let old = KeyOwnership<String>.Owner { try await Task.sleep(for: .seconds(60)) }
    ownership.claim("key", by: old)

    let fill = await ownership.takeOver("key") {
      KeyOwnership<String>.Owner { try await Task.sleep(for: .seconds(60)) }
    }
    #expect(old.isCancelled)
    #expect(ownership.owner(of: "key") == fill)
    // The drained owner finishing late must not unprotect its successor.
    ownership.release("key", ifOwnedBy: old)
    #expect(ownership.owner(of: "key") == fill)
    fill.cancel()
  }

  @Test("Concurrent take-overs of one key leave exactly one writer running", .bug(id: "735"))
  func concurrentTakeOversLeaveOneWriter() async throws {
    let ownership = KeyOwnership<String>()
    let latch = Latch()
    let old = KeyOwnership<String>.Owner {
      await latch.wait()
      try Task.checkCancellation()
    }
    ownership.claim("key", by: old)

    let takers = (0..<3).map { _ in
      Task { @MainActor in
        await ownership.takeOver("key") {
          KeyOwnership<String>.Owner { try await Task.sleep(for: .seconds(60)) }
        }
      }
    }
    try await Task.sleep(for: .milliseconds(20))
    await latch.release()
    var fills: [KeyOwnership<String>.Owner] = []
    for taker in takers { fills.append(await taker.value) }

    let holder = try #require(ownership.owner(of: "key"))
    #expect(fills.filter { !$0.isCancelled } == [holder])
    for fill in fills { fill.cancel() }
  }

  @Test("A throwing start claims nothing")
  func takeOverStartThrows() async throws {
    let ownership = KeyOwnership<String>()
    let old = KeyOwnership<String>.Owner { try await Task.sleep(for: .seconds(60)) }
    ownership.claim("key", by: old)

    await #expect(throws: WriteFailed.self) {
      try await ownership.takeOver("key") { throw WriteFailed() }
    }
    #expect(old.isCancelled)
    #expect(!ownership.isOwned("key"))
  }

  @Test("A write owns its keys for its whole duration and releases them afterwards")
  func withOwnershipHoldsAcrossAwaits() async throws {
    let ownership = KeyOwnership<String>()
    let latch = Latch()

    let writer = Task { @MainActor in
      try await ownership.withOwnership(of: ["a", "b"]) {
        await latch.wait()
      }
    }
    try await waitUntil { ownership.isOwned("a") }
    #expect(ownership.isOwned("b"))
    #expect(Set(ownership.ownedKeys) == ["a", "b"])

    await latch.release()
    #expect(try await writer.value == true)
    #expect(!ownership.isOwned("a"))
    #expect(!ownership.isOwned("b"))
  }

  @Test(
    "Draining any one key of a multi-key write stops it, without touching keys it never owned",
    .bug(id: "716"))
  func drainOneKeyOfSweep() async throws {
    // The reachability-sweep race: a fill for a collected key drains the sweep
    // and gets the key; a fill for a key the sweep never observed is not held
    // up by it at all.
    let ownership = KeyOwnership<String>()

    let sweep = Task { @MainActor in
      try await ownership.withOwnership(of: ["collected-1", "collected-2"]) {
        try await Task.sleep(for: .seconds(60))
      }
    }
    try await waitUntil { ownership.isOwned("collected-2") }
    #expect(!ownership.isOwned("never-cached"))

    await ownership.drain("collected-2")
    let fill = KeyOwnership<String>.Owner { try await Task.sleep(for: .seconds(60)) }
    ownership.claim("collected-2", by: fill)

    #expect(try await sweep.value == false, "a drained write reports that it was taken over")
    // The sweep's release left the fill's claim alone and dropped its own.
    #expect(ownership.isOwned("collected-2"))
    #expect(!ownership.isOwned("collected-1"))
    fill.cancel()
  }

  @Test("A caller cancelled while its write runs sees cancellation, not success")
  func callerCancellationIsReported() async throws {
    // The cancelled-sweep-recorded-as-successful family: the unstructured write
    // does not inherit the caller's cancellation and completes normally, so
    // without the backstop the caller would read it as work done.
    let ownership = KeyOwnership<String>()
    let latch = Latch()
    let log = Log()

    let caller = Task { @MainActor in
      try await ownership.withOwnership(of: ["key"]) {
        await latch.wait()
        log.append(Task.isCancelled ? "write cancelled" : "write completed")
      }
    }
    try await waitUntil { ownership.isOwned("key") }
    caller.cancel()
    await latch.release()

    await #expect(throws: CancellationError.self) { try await caller.value }
    #expect(log.entries == ["write completed"])
    #expect(!ownership.isOwned("key"))
  }

  @Test("A caller cancelled while its write is drained still sees cancellation")
  func callerCancellationWinsOverDrain() async throws {
    let ownership = KeyOwnership<String>()

    let caller = Task { @MainActor in
      try await ownership.withOwnership(of: ["key"]) {
        try await Task.sleep(for: .seconds(60))
      }
    }
    try await waitUntil { ownership.isOwned("key") }
    caller.cancel()
    await ownership.drain("key")

    await #expect(throws: CancellationError.self) { try await caller.value }
    #expect(!ownership.isOwned("key"))
  }

  @Test("A failing write propagates its error and releases its keys")
  func writeErrorPropagates() async throws {
    let ownership = KeyOwnership<String>()
    await #expect(throws: WriteFailed.self) {
      try await ownership.withOwnership(of: ["key"]) { throw WriteFailed() }
    }
    #expect(!ownership.isOwned("key"))
  }
}
