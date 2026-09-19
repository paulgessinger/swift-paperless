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
@MainActor
public final class KeyOwnership<Key: Hashable & Sendable> {
  public typealias Owner = Task<Void, any Error>

  private var owners: [Key: Owner] = [:]

  public init() {}

  /// Whether some writer currently owns `key`.
  public func isOwned(_ key: Key) -> Bool { owners[key] != nil }

  /// The writer currently owning `key`, if any — for callers that wait for the
  /// key to settle without taking it over.
  public func owner(of key: Key) -> Owner? { owners[key] }

  /// Every key currently owned, as of this call.
  public var ownedKeys: Dictionary<Key, Owner>.Keys { owners.keys }

  /// Register `owner` as `key`'s writer.
  ///
  /// Unconditional: whatever owned the key before is replaced *without* being
  /// cancelled. Callers that want exclusion use ``takeOver(_:start:)``.
  public func claim(_ key: Key, by owner: Owner) {
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
  public func drain(_ key: Key) async {
    while let owner = owners[key] {
      owner.cancel()
      _ = try? await owner.value
      release(key, ifOwnedBy: owner)
    }
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
  /// - Returns: The owner `start` created, now registered against `key`.
  @discardableResult
  public func takeOver(_ key: Key, start: () throws -> Owner) async rethrows -> Owner {
    await drain(key)
    let owner = try start()
    claim(key, by: owner)
    return owner
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
  /// - Returns: `true` if the write completed, `false` if it was drained.
  public func withOwnership(
    of keys: Set<Key>,
    perform write: @escaping @Sendable () async throws -> Void
  ) async throws -> Bool {
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
