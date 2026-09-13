//
//  TaskSlot.swift
//  Common
//

import Foundation
import Observation

/// One main-actor single-flight: at most one unstructured task in the slot, which
/// every caller arriving while it runs joins instead of starting a second.
///
/// This is the idiom that used to be written out by hand at each site:
///
/// ```swift
/// if let slot { return await slot.value }
/// let task = Task { … }
/// slot = task
/// defer { if slot == task { slot = nil } }   // retract only our own
/// return await task.value
/// ```
///
/// ## The invariant
///
/// **Claiming and clearing the slot never suspends, so the slot cannot be
/// claimed twice.** It holds because the type is `@MainActor` and every mutation
/// of ``isOccupied``'s backing task happens in a synchronous stretch of code:
/// ``joinOrStart(_:)`` checks for a task in flight and, if there is none, creates
/// and stores the new one without an `await` in between; the decide closure of
/// ``joinOrStart(ifIdle:)`` is synchronous for exactly that reason. The only
/// suspension is awaiting the task's value, which happens *after* the claim.
///
/// A main-actor caller also enters these methods without suspending — calling
/// an async function on the executor you are already on does not give it up —
/// so state the caller checked just before the call (say, "the slot is empty"
/// after ``waitUntilIdle()``) is still true at the claim.
///
/// ## What it deliberately does not do
///
/// - It does not propagate the caller's cancellation into the task. The task is
///   unstructured and shared: a joiner (or the starter) going away must not
///   tear down the work under the others. A caller that needs to know whether
///   *it* was cancelled has to ask `Task.checkCancellation()` itself.
/// - It is not ``SingleFlight``. That type is keyed, lock-based and callable
///   from any isolation, retracts its entry from inside the operation, fans
///   progress out to joiners, and cannot be cancelled. A slot is main-actor
///   state that views observe (``isOccupied``), retracts from the *starter*
///   once the value is back, and has to be retired — cancelled and emptied at
///   once — when the work in it goes stale.
@MainActor
@Observable
public final class TaskSlot<Success: Sendable, Failure: Error> {
  /// The task in flight. Mirrored into ``isOccupied`` on every assignment, so
  /// there is no mutation that can forget to update the observed flag.
  ///
  /// Unobserved because `deinit` has to read it, and deinit is nonisolated.
  @ObservationIgnored private var task: Task<Success, Failure>? {
    didSet {
      let occupied = task != nil
      if occupied != isOccupied {
        isOccupied = occupied
      }
    }
  }

  /// Whether a task is in the slot. Observable; flips synchronously with the
  /// claim and the retraction.
  public private(set) var isOccupied = false

  public init() {}

  /// Belt and braces, not a path anything relies on: a starter awaiting
  /// ``joinOrStart(_:)`` retains the slot, and it retracts its task before
  /// returning, so a slot is in practice always empty by the time it goes.
  deinit {
    task?.cancel()
  }

  /// Cancel the task in flight, if any, and empty the slot immediately.
  ///
  /// The next caller starts fresh rather than joining work that is still
  /// winding down — which is the point: the retired task's result belongs to a
  /// world that no longer exists. When the retired task's starter resumes, its
  /// retraction finds a different task (or none) in the slot and leaves it.
  public func retire() {
    task?.cancel()
    task = nil
  }

  /// Empty the slot — but only if it still holds `finished`. A retire, or a
  /// replacement started after one, may own the slot by the time the starter
  /// resumes, and clearing it blindly would break the newer task's coalescing.
  /// Synchronous, like every other mutation of the slot.
  private func retract(_ finished: Task<Success, Failure>) {
    if task == finished {
      task = nil
    }
  }
}

extension TaskSlot where Failure == Never {
  /// Join the task in flight, or start one running `operation`.
  public func joinOrStart(_ operation: @escaping @MainActor () async -> Success) async -> Success {
    if let task { return await task.value }
    return await start(operation)
  }

  /// Join the task in flight, or ask `makeOperation` whether to start one.
  ///
  /// `makeOperation` only runs when the slot is empty, and returning `nil`
  /// declines — nothing is claimed and this returns `nil`. It is synchronous on
  /// purpose: that is what guarantees nothing can claim the slot between the
  /// emptiness check and the claim.
  public func joinOrStart(ifIdle makeOperation: () -> (@MainActor () async -> Success)?) async
    -> Success?
  {
    if let task { return await task.value }
    guard let operation = makeOperation() else { return nil }
    return await start(operation)
  }

  private func start(_ operation: @escaping @MainActor () async -> Success) async -> Success {
    let task = Task { @MainActor in await operation() }
    self.task = task
    defer { retract(task) }
    return await task.value
  }
}

extension TaskSlot where Failure == any Error {
  /// Join the task in flight, or start one running `operation`. Rethrows the
  /// task's error to the starter and to every joiner alike.
  public func joinOrStart(_ operation: @escaping @MainActor () async throws -> Success) async throws
    -> Success
  {
    if let task { return try await task.value }
    return try await start(operation)
  }

  /// Join the task in flight, or ask `makeOperation` whether to start one. See
  /// the non-throwing overload for why `makeOperation` is synchronous.
  public func joinOrStart(ifIdle makeOperation: () -> (@MainActor () async throws -> Success)?)
    async throws -> Success?
  {
    if let task { return try await task.value }
    guard let operation = makeOperation() else { return nil }
    return try await start(operation)
  }

  /// Wait until the slot is empty, ignoring the outcome of whatever was in it.
  ///
  /// Loops because the task we waited for may have been followed by another
  /// by the time we resume. On return the slot is empty *at this instant*, so a
  /// caller that claims it before its next `await` is guaranteed to be the only
  /// claimant — the shape for "re-evaluate after the in-flight attempt, then
  /// maybe start my own" rather than joining someone else's result.
  public func waitUntilIdle() async {
    while let task {
      _ = try? await task.value
      retract(task)
    }
  }

  private func start(_ operation: @escaping @MainActor () async throws -> Success) async throws
    -> Success
  {
    let task = Task { @MainActor in try await operation() }
    self.task = task
    defer { retract(task) }
    return try await task.value
  }
}
