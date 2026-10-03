//
//  KeyOwnership.swift
//  Common
//

import Foundation

/// Exclusive writers per key, held *across* suspension points.
///
/// Actor isolation ends at the first `await`; a writer that pages dozens of
/// network requests into one key needs exclusion that outlives every one of
/// them. Ownership is modelled as an unstructured task registered against the
/// key: it is the owner while it is registered, a newcomer takes the key over
/// with ``takeOver(_:start:)`` (drain — cancel, then await it actually stopping
/// — until nobody owns the key, then claim), a writer that must step over a key
/// already in use asks ``isOwned(_:)`` and then runs under
/// ``withOwnership(of:perform:)``.
///
/// The policy is the opposite of ``SingleFlight`` and ``TaskSlot``: a second
/// caller for a key does not *join* the first, it *replaces* it.
///
/// ## The invariant
///
/// **Claiming and releasing never suspends, so two writers cannot both hold a
/// key.** The type is `@MainActor` and ``claim(_:by:)``,
/// ``release(_:ifOwnedBy:)`` and ``isOwned(_:)`` are synchronous. The only
/// suspension in ``drain(_:)`` is awaiting a departing owner, and it re-checks
/// the key after every one, returning only once the key is free.
/// ``takeOver(_:start:)`` then starts and claims the new owner synchronously,
/// so nothing can claim between that final "key is free" check and the claim.
///
/// Draining *once* is not enough. Several newcomers can be waiting on the same
/// departing owner; the first to resume claims, and a later one that went
/// straight on to claim would replace it *without cancelling it* — two writers
/// on one key, the very thing this type exists to prevent (#735).
///
/// ``withOwnership(of:perform:)`` claims before its first `await`, and a
/// main-actor caller enters it without suspending, so a snapshot of
/// ``ownedKeys`` the caller took just before the call is still current at the
/// claim.
///
/// ## Pending take-overs
///
/// A caller inside ``takeOver(_:start:)`` is counted against its key from the
/// moment it enters until it returns or throws, not only once it has claimed.
/// Otherwise the key would read as free while that caller waits to resume after
/// the departing owner released it, and a sweep could claim it or a waiter
/// could return just before the take-over's claim (#775). So ``isOwned(_:)``,
/// ``ownedKeys`` and ``waitUntilFree(_:)`` mean "owned, or about to be".
/// ``drain(_:)`` and ``owner(of:)`` see registered owners only: a take-over
/// drains the writer in its way, not the other take-overs queued beside it.
@MainActor
public final class KeyOwnership<Key: Hashable & Sendable> {
  public typealias Owner = Task<Void, any Error>

  private var owners: [Key: Owner] = [:]

  /// Callers currently inside ``takeOver(_:start:)``, per key. Absent rather
  /// than zero.
  private var pendingTakeOvers: [Key: Int] = [:]

  /// ``waitUntilFree(_:)`` callers parked on a key that has pending take-overs
  /// but no registered owner, resumed whenever a take-over of that key ends.
  private var freeWaiters: [Key: [UInt64: CheckedContinuation<Void, Never>]] = [:]
  private var nextWaiterID: UInt64 = 0

  public init() {}

  /// Whether some writer owns `key`, or a ``takeOver(_:start:)`` of it is in
  /// progress.
  public func isOwned(_ key: Key) -> Bool {
    owners[key] != nil || pendingTakeOvers[key] != nil
  }

  /// The writer registered against `key`, if any. Excludes pending take-overs.
  func owner(of key: Key) -> Owner? { owners[key] }

  /// Every key ``isOwned(_:)`` reports, as of this call.
  public var ownedKeys: Set<Key> {
    Set(owners.keys).union(pendingTakeOvers.keys)
  }

  /// Register `owner` as `key`'s writer.
  ///
  /// Unconditional: whatever owned the key before is replaced *without* being
  /// cancelled. Not public for that reason: outside callers take a key over
  /// with ``takeOver(_:start:)``, or write a key they checked is free under
  /// ``withOwnership(of:perform:)``, and neither can leave a replaced writer
  /// running.
  func claim(_ key: Key, by owner: Owner) {
    owners[key] = owner
  }

  /// Release `key` — but only if `owner` still holds it. A newer writer may have
  /// drained and replaced `owner` while it was finishing, and clearing blindly
  /// would leave that writer unprotected.
  public func release(_ key: Key, ifOwnedBy owner: Owner) {
    if owners[key] == owner {
      owners[key] = nil
    }
  }

  /// Stop whatever owns `key` and wait for it to actually stop, until nobody
  /// owns it.
  ///
  /// Cancellation is cooperative, so returning without the await would leave a
  /// writer alive across the caller's own write. The owner's outcome is its own
  /// business; all this needs is for it to have stopped.
  ///
  /// Loops, as ``TaskSlot/waitUntilIdle()`` does: while this was waiting,
  /// another drainer of the same owner may have resumed first and claimed the
  /// key, or a writer may have claimed it in the moment between the owner
  /// releasing it and this resuming. Either is drained in turn, so the key is
  /// free when this returns — the last check and the return are one main-actor
  /// job, with no suspension in between.
  ///
  /// A drainer cancelled *itself* stops here instead, with
  /// `CancellationError`. `await owner.value` is not interruptible, so such a
  /// caller resumes anyway, and without the check it would go on to cancel
  /// whatever it finds next — after several drainers waited on one owner, that
  /// is the *successor* a still-live caller is depending on. It would stop that
  /// successor and then claim a replacement its own caller cancels the instant
  /// it exists (``takeOver(_:start:)`` claims without suspending, so the caller's
  /// cancellation handler is the very next thing to run): two writers killed and
  /// the key left with nobody refreshing it (#735). So cancellation is checked
  /// before every owner this would stop, and once more before returning, where
  /// the caller's claim follows. A cancelled drainer has cancelled nothing and
  /// leaves the key exactly as it found it.
  public func drain(_ key: Key) async throws {
    while let owner = owners[key] {
      try Task.checkCancellation()
      owner.cancel()
      _ = try? await owner.value
      release(key, ifOwnedBy: owner)
    }
    try Task.checkCancellation()
  }

  /// Take `key` over: drain it until nobody owns it, then register the owner
  /// `start` creates.
  ///
  /// `start` is synchronous, so the compiler rules out a suspension between
  /// ``drain(_:)`` finding the key free and the claim — nothing else can claim
  /// in that gap. If `start` throws, nothing is claimed and the key stays free.
  ///
  /// The new owner's registration is the caller's to retract, with
  /// ``release(_:ifOwnedBy:)`` once it has stopped: a newer caller may have
  /// taken the key over meanwhile.
  ///
  /// Throws `CancellationError` without claiming anything if the *caller* was
  /// cancelled while draining — see ``drain(_:)``.
  ///
  /// The key counts as owned for the whole call (see *Pending take-overs*).
  /// The count is taken before the first suspension and dropped in a `defer`,
  /// so every exit — claim, a throwing `start`, cancellation — drops it; on
  /// success the claim is already in place when it does.
  ///
  /// - Returns: The owner `start` created, now registered against `key`.
  @discardableResult
  public func takeOver(_ key: Key, start: () throws -> Owner) async throws -> Owner {
    pendingTakeOvers[key, default: 0] += 1
    defer { endPendingTakeOver(key) }
    try await drain(key)
    let owner = try start()
    claim(key, by: owner)
    return owner
  }

  private func endPendingTakeOver(_ key: Key) {
    let remaining = pendingTakeOvers[key, default: 1] - 1
    pendingTakeOvers[key] = remaining > 0 ? remaining : nil
    // Waiters re-check: the key is now claimed, still pending, or free.
    guard let waiters = freeWaiters.removeValue(forKey: key) else { return }
    for waiter in waiters.values { waiter.resume() }
  }

  /// Suspend until `key` is free — no registered owner and no take-over in
  /// progress — without taking it over. Returns early if the calling task is
  /// cancelled.
  ///
  /// Owners are awaited, not cancelled. A finished owner is released here
  /// rather than waited on until its own caller retracts it; it is no longer
  /// writing. Waiting on a pending take-over parks until that take-over ends,
  /// then re-checks. Cancellation interrupts that park, but not an
  /// `await owner.value`, so a cancelled caller returns once the owner it is
  /// awaiting has stopped.
  ///
  /// The key is free when this returns uncancelled, as of that main-actor job;
  /// anything may claim it at the caller's next suspension.
  public func waitUntilFree(_ key: Key) async {
    while !Task.isCancelled {
      if let owner = owners[key] {
        _ = try? await owner.value
        release(key, ifOwnedBy: owner)
      } else if pendingTakeOvers[key] != nil {
        await waitForPendingTakeOverToEnd(key)
      } else {
        return
      }
    }
  }

  private func waitForPendingTakeOverToEnd(_ key: Key) async {
    let id = nextWaiterID
    nextWaiterID += 1
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        // Cancelled before this registered: the handler has nothing to resume.
        if Task.isCancelled {
          continuation.resume()
        } else {
          freeWaiters[key, default: [:]][id] = continuation
        }
      }
    } onCancel: {
      Task { @MainActor in self.resumeFreeWaiter(key, id: id) }
    }
  }

  /// No-op if a take-over ending already resumed it.
  private func resumeFreeWaiter(_ key: Key, id: UInt64) {
    guard let waiter = freeWaiters[key]?.removeValue(forKey: id) else { return }
    if freeWaiters[key]?.isEmpty == true { freeWaiters[key] = nil }
    waiter.resume()
  }

  /// Run `write` as the owner of every key in `keys`, for its whole duration.
  ///
  /// The write runs on an unstructured task, which is what lets it be the
  /// registered owner — and lets a newcomer's ``drain(_:)`` cancel it without
  /// cancelling *us*. Every key is released afterwards, each only if still ours.
  ///
  /// Two cancellations are in play and they mean different things:
  ///
  /// - The *write's*: someone drained one of the keys. The write stopped, which
  ///   is not an error for the caller; this returns `false`.
  /// - The *caller's*: the unstructured write does not inherit it, so
  ///   `write` can return normally for a caller that was cancelled meanwhile.
  ///   This asks `Task.checkCancellation()` once the write has settled, drained
  ///   or not, so a cancelled caller always sees `CancellationError` instead of
  ///   an outcome it would record as work done.
  ///
  /// Any other error from `write` propagates as-is.
  ///
  /// This is for a writer that *steps over* keys in use rather than taking them
  /// over, so every key must be free, pending take-overs included: the caller
  /// checks ``isOwned(_:)`` (or ``ownedKeys``) and gets here without
  /// suspending. Claiming an owned key would replace its writer without
  /// stopping it, so that is asserted against rather than done silently; a
  /// writer that wants a busy key uses ``takeOver(_:start:)``.
  ///
  /// - Returns: `true` if the write completed, `false` if it was drained.
  public func withOwnership(
    of keys: Set<Key>,
    perform write: @escaping @Sendable () async throws -> Void
  ) async throws -> Bool {
    assert(
      keys.allSatisfy { !isOwned($0) },
      "withOwnership would replace a running writer without stopping it")
    let owner = Owner { try await write() }
    for key in keys { claim(key, by: owner) }
    defer {
      for key in keys { release(key, ifOwnedBy: owner) }
    }
    let completed: Bool
    do {
      try await owner.value
      completed = true
    } catch is CancellationError {
      completed = false
    }
    try Task.checkCancellation()
    return completed
  }
}
