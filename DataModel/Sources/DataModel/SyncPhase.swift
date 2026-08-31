//
//  SyncPhase.swift
//  DataModel
//

/// One unit of sync work for a single server.
///
/// Cases are declared in **dependency order**, and ``SyncPhases/ordered``
/// relies on that: the reconcile needs the saved views the element sync brings
/// down, and the fill pages rows the reconcile has already settled. A new phase
/// must be inserted where it belongs in the sequence rather than appended.
public enum SyncPhase: Int, Sendable, Equatable, CaseIterable, Comparable {
  /// Tags, correspondents, saved views… — the element collections.
  case elements
  /// Remote deletes, the changed-metadata delta, saved-view membership.
  case reconcile
  /// The proactive *Entire library* fill: every query's pages, then the
  /// per-document details.
  case fill

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The phases a sync pass should run.
///
/// A set rather than a sequence, deliberately: *which* work to do is a decision
/// (``SyncPlan`` makes it, from the server's mode and the link), but the order
/// to do it in is not a caller's choice at all. ``ordered`` is the single
/// canonical sequence, so no caller can run a phase before one it depends on —
/// which used to be upheld only by every call site happening to agree.
public struct SyncPhases: Sendable, Equatable, ExpressibleByArrayLiteral {
  private var storage: Set<SyncPhase>

  public init(_ phases: some Sequence<SyncPhase>) {
    storage = Set(phases)
  }

  public init(arrayLiteral elements: SyncPhase...) {
    storage = Set(elements)
  }

  /// Elements plus the reconcile sweeps: what every sync does, regardless of
  /// the server's offline mode or how expensive the link is.
  public static let cheap: Self = [.elements, .reconcile]

  /// The cheap phases plus the proactive fill.
  public static let full: Self = [.elements, .reconcile, .fill]

  /// No network work at all — an uncredentialed server.
  ///
  /// Not spelled `none`: that shadows `Optional.none`, and every use site here
  /// is a context where an optional is also plausible, so the compiler cannot
  /// tell which one a bare `.none` means.
  public static let nothing: Self = []

  public var isEmpty: Bool { storage.isEmpty }

  public func contains(_ phase: SyncPhase) -> Bool { storage.contains(phase) }

  /// The phases in dependency order.
  public var ordered: [SyncPhase] { storage.sorted() }
}
