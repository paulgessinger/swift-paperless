//
//  SyncCondition.swift
//  DataModel
//

/// Whether the proactive sync sweeps (the entire-library fill, a multi-server
/// warm sweep) may run right now, on one server. The single place this
/// decision is made — every caller (foreground, background, per-server sweep)
/// constructs one of these and reads ``allowsProactiveSync`` rather than
/// re-deriving the formula, which is what let it drift out of sync across
/// call sites before.
///
/// Interactive work the user asked for (opening a document, pull-to-refresh,
/// search, "Sync now") is never gated on this.
public struct SyncCondition: Equatable, Sendable {
  /// What the path costs — a fact about the network, measured elsewhere.
  public var cost: LinkCost
  /// This server's own opt-in to proactive syncing on a metered link — a
  /// setting, and the reason this type exists separately from ``LinkCost``:
  /// two servers on the same link can legitimately answer differently.
  public var syncOverCellular: Bool

  public init(cost: LinkCost, syncOverCellular: Bool) {
    self.cost = cost
    self.syncOverCellular = syncOverCellular
  }

  /// Low Data Mode always wins: it's an explicit instruction from the user to
  /// the whole system, not a guess about the link, so the per-server opt-in
  /// does not override it. The opt-in is what `isExpensive` alone is for.
  public var allowsProactiveSync: Bool {
    cost.isConstrained ? false : (syncOverCellular || !cost.isExpensive)
  }
}
