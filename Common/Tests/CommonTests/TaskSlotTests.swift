//
//  TaskSlotTests.swift
//  Common
//

import Foundation
import Testing

@testable import Common

/// Parks callers until `release()`; cancellation does not unpark them, so a test
/// controls exactly when an operation finishes.
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

private struct BuildFailed: Error {}

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
struct TaskSlotTests {
  @Test("A second caller joins the task in flight instead of starting another")
  func joinsInFlightTask() async throws {
    let slot = TaskSlot<Int, Never>()
    let latch = Latch()
    var starts = 0

    let first = Task { @MainActor in
      await slot.joinOrStart {
        starts += 1
        await latch.wait()
        return 42
      }
    }
    try await waitUntil { slot.isOccupied }
    let second = Task { @MainActor in
      await slot.joinOrStart {
        starts += 1
        return -1
      }
    }
    // The joiner is parked on the same task; the slot is still the first's.
    // Let the other main-actor task reach its `await` before going on.
    try await Task.sleep(for: .milliseconds(20))
    #expect(slot.isOccupied)

    await latch.release()
    #expect(await first.value == 42)
    #expect(await second.value == 42)
    #expect(starts == 1)
    #expect(!slot.isOccupied)
  }

  @Test("Joiners of a throwing slot see the same error as the starter")
  func rethrowsToJoiners() async throws {
    let slot = TaskSlot<Void, any Error>()
    let latch = Latch()

    let first = Task { @MainActor in
      try await slot.joinOrStart {
        await latch.wait()
        throw BuildFailed()
      }
    }
    try await waitUntil { slot.isOccupied }
    let second = Task { @MainActor in
      try await slot.joinOrStart {}
    }
    // Let the other main-actor task reach its `await` before going on.
    try await Task.sleep(for: .milliseconds(20))
    await latch.release()

    await #expect(throws: BuildFailed.self) { try await first.value }
    await #expect(throws: BuildFailed.self) { try await second.value }
    #expect(!slot.isOccupied)
  }

  @Test("The decide closure only runs on an empty slot, and declining claims nothing")
  func ifIdleDeclines() async throws {
    let slot = TaskSlot<Int, Never>()
    var asked = 0

    let declined = await slot.joinOrStart(ifIdle: {
      asked += 1
      return nil
    })
    #expect(declined == nil)
    #expect(asked == 1)
    #expect(!slot.isOccupied)

    let latch = Latch()
    let starter = Task { @MainActor in
      await slot.joinOrStart {
        await latch.wait()
        return 7
      }
    }
    try await waitUntil { slot.isOccupied }
    let joiner = Task { @MainActor in
      await slot.joinOrStart(ifIdle: {
        asked += 1
        return nil
      })
    }
    // Let the other main-actor task reach its `await` before going on.
    try await Task.sleep(for: .milliseconds(20))
    await latch.release()
    #expect(await starter.value == 7)
    // Joined, not asked: the in-flight value comes back despite the decline.
    #expect(await joiner.value == 7)
    #expect(asked == 1)
  }

  @Test(
    "Retire cancels and empties the slot, and the next caller starts fresh",
    .bug(id: "716"))
  func retireStartsFresh() async throws {
    // The rebuild scenario: a follow-up caller after a connection change must
    // not join the element sync still running against the old repository.
    let slot = TaskSlot<String, any Error>()
    let staleLatch = Latch()

    let stale = Task { @MainActor in
      try await slot.joinOrStart {
        await staleLatch.wait()
        try Task.checkCancellation()
        return "stale"
      }
    }
    try await waitUntil { slot.isOccupied }

    slot.retire()
    #expect(!slot.isOccupied)

    let fresh = try await slot.joinOrStart { "fresh" }
    #expect(fresh == "fresh")

    await staleLatch.release()
    await #expect(throws: CancellationError.self) { try await stale.value }
    #expect(!slot.isOccupied)
  }

  @Test("A retired task's starter does not retract the task that replaced it")
  func retractsOnlyItsOwnTask() async throws {
    let slot = TaskSlot<String, Never>()
    let oldLatch = Latch()
    let newLatch = Latch()

    let old = Task { @MainActor in
      await slot.joinOrStart {
        await oldLatch.wait()
        return "old"
      }
    }
    try await waitUntil { slot.isOccupied }
    slot.retire()

    let replacement = Task { @MainActor in
      await slot.joinOrStart {
        await newLatch.wait()
        return "new"
      }
    }
    try await waitUntil { slot.isOccupied }

    // The old starter resumes while the replacement is in flight.
    await oldLatch.release()
    #expect(await old.value == "old")
    #expect(slot.isOccupied, "the replacement must still own the slot")

    // …so a third caller still coalesces onto the replacement.
    let joiner = Task { @MainActor in
      await slot.joinOrStart { "third" }
    }
    // Let the other main-actor task reach its `await` before going on.
    try await Task.sleep(for: .milliseconds(20))
    await newLatch.release()
    #expect(await replacement.value == "new")
    #expect(await joiner.value == "new")
    #expect(!slot.isOccupied)
  }

  @Test("Cancelling a caller does not cancel the shared task")
  func callerCancellationDoesNotReachTask() async throws {
    let slot = TaskSlot<Bool, Never>()
    let latch = Latch()

    let caller = Task { @MainActor in
      await slot.joinOrStart {
        await latch.wait()
        return Task.isCancelled
      }
    }
    try await waitUntil { slot.isOccupied }
    caller.cancel()
    await latch.release()
    // The unstructured task did not inherit the caller's cancellation; noticing
    // it is the caller's job.
    #expect(await caller.value == false)
  }

  @Test("Waiting for idle ignores a failed attempt and leaves the slot claimable")
  func waitUntilIdleThenStart() async throws {
    // The repository-build scenario: a second caller waits out the first build,
    // does not inherit its failure, and re-evaluates before starting its own.
    let slot = TaskSlot<Int, any Error>()
    let latch = Latch()

    let failing = Task { @MainActor in
      try await slot.joinOrStart {
        await latch.wait()
        throw BuildFailed()
      }
    }
    try await waitUntil { slot.isOccupied }

    let waiter = Task { @MainActor () -> Int in
      await slot.waitUntilIdle()
      // Nothing suspends between the wait returning and this claim.
      #expect(!slot.isOccupied)
      return try await slot.joinOrStart { 2 }
    }
    // Let the other main-actor task reach its `await` before going on.
    try await Task.sleep(for: .milliseconds(20))
    await latch.release()

    await #expect(throws: BuildFailed.self) { try await failing.value }
    #expect(try await waiter.value == 2)
    #expect(!slot.isOccupied)
  }

  @Test("Waiting for idle also waits out a task that replaced the first one")
  func waitUntilIdleLoops() async throws {
    let slot = TaskSlot<Int, any Error>()
    let firstLatch = Latch()
    let secondLatch = Latch()

    let first = Task { @MainActor in
      try await slot.joinOrStart {
        await firstLatch.wait()
        return 1
      }
    }
    try await waitUntil { slot.isOccupied }

    var waited = false
    let waiter = Task { @MainActor in
      await slot.waitUntilIdle()
      waited = true
    }
    // Let the other main-actor task reach its `await` before going on.
    try await Task.sleep(for: .milliseconds(20))

    slot.retire()
    let second = Task { @MainActor in
      try await slot.joinOrStart {
        await secondLatch.wait()
        return 2
      }
    }
    try await waitUntil { slot.isOccupied }

    await firstLatch.release()
    _ = try? await first.value
    try await Task.sleep(for: .milliseconds(20))
    #expect(!waited, "the waiter must not return while the replacement is in flight")

    await secondLatch.release()
    #expect(try await second.value == 2)
    await waiter.value
    #expect(waited)
    #expect(!slot.isOccupied)
  }
}
