//
//  LinkCost.swift
//  DataModel
//

/// What the current network path costs, as one value.
///
/// A type rather than a pair of `Bool`s because the two facts are only ever
/// meaningful together, and travelled together anyway: from the path monitor,
/// through the scheduler, into ``SyncCondition``. Passed loose they were
/// re-packed at every hop, and each hop was free to drop one, reorder them, or
/// invent a default — which is how a "cost" ends up being a policy in disguise.
///
/// This is a *fact about the link*, and nothing more. What to do about it is
/// ``SyncCondition``'s to say, because that also needs the server's own opt-in,
/// which is not a property of the network.
public struct LinkCost: Equatable, Sendable {
  /// The path is metered — cellular, or a personal hotspot.
  public var isExpensive: Bool
  /// Low Data Mode is on for this network.
  public var isConstrained: Bool

  public init(isExpensive: Bool, isConstrained: Bool) {
    self.isExpensive = isExpensive
    self.isConstrained = isConstrained
  }

  /// Wi‑Fi or wired, no Low Data Mode: proactive work may run freely.
  public static let unrestricted = LinkCost(isExpensive: false, isConstrained: false)

  /// The stand-in for a link nobody could measure — no path monitor is running,
  /// or none has reported yet.
  ///
  /// Deliberately the most restrictive value there is: guessing "cheap" spends
  /// the user's data plan on a guess, where guessing "costly" only defers work
  /// to the next trigger. It used to appear as a bare `(true, true)` tuple with
  /// no name and no reason given.
  ///
  /// Behaviourally indistinguishable from a genuinely restricted link today.
  /// Telling the two apart only becomes possible once something can actually
  /// probe the path — until then there is nothing a caller could do differently.
  public static let unknown = LinkCost(isExpensive: true, isConstrained: true)
}
