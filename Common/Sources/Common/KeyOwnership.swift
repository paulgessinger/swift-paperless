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
/// by ``drain(_:)``-ing it (cancel, then await it actually stopping) before
/// claiming, and a reader that must not interleave with a writer asks
/// ``isOwned(_:)``.
///
/// The policy is the opposite of ``SingleFlight`` and ``TaskSlot``: a second
/// caller for a key does not *join* the first, it *replaces* it.
///
/// ## The invariant
///
/// **Claiming and releasing never suspends, so two writers cannot both hold a
/// key.** The type is `@MainActor` and ``claim(_:by:)``,
/// ``release(_:ifOwnedBy:)`` and ``isOwned(_:)`` are synchronous. The single
/// suspension in ``drain(_:)`` is awaiting the departing owner; it releases the
/// key only if that owner still holds it afterwards. What a caller does between
/// `drain` returning and its own `claim` is its business — keep it synchronous,
/// or someone else can claim in the gap.
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

  /// Every key currently owned, as of this call.
  public var ownedKeys: Dictionary<Key, Owner>.Keys { owners.keys }

  /// Register `owner` as `key`'s writer.
  ///
  /// Unconditional: whatever owned the key before is replaced *without* being
  /// cancelled. Callers that want exclusion ``drain(_:)`` first.
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

  /// Stop the writer that currently owns `key` and wait for it to actually
  /// stop.
  ///
  /// Cancellation is cooperative, so returning without the await would leave a
  /// writer alive across the caller's own write. The owner's outcome is its own
  /// business; all this needs is for it to have stopped.
  public func drain(_ key: Key) async {
    guard let owner = owners[key] else { return }
    owner.cancel()
    _ = try? await owner.value
    release(key, ifOwnedBy: owner)
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
