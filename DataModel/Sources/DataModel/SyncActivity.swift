//
//  SyncActivity.swift
//  DataModel
//

import Foundation

/// What the offline sync is doing right now, for the Offline & Sync screen.
///
/// The screen used to infer this from two booleans, which could only ever say
/// "something is happening" — and only for the library fill, so the detail fill
/// read as idle throughout. That is not enough for a pass with no cap on it: a
/// first cold fill of a large library runs for a long time and the user needs to
/// see it moving, and which stage it is in, rather than a spinner that might
/// equally be stuck.
///
/// Several of these run at once, so the store publishes *all* of them rather
/// than picking one — see `AppShared.ServerSession.syncActivities`.
///
/// In `DataModel` rather than `AppShared` for the same reason as
/// ``OfflineLibrarySize``: the ordering rule is easy to regress silently and
/// `AppShared` has no test target.
public struct SyncActivity: Sendable, Equatable, Identifiable {
  /// Declaration order is the display order — see ``SyncActivity/id``.
  public enum Stage: Sendable, Equatable, CaseIterable {
    /// Tags, correspondents, saved views… — the element collections.
    case elementSync
    /// Paging saved views and the default list into `query_order`.
    case libraryFill
    /// Per-document notes and file metadata.
    case detailFill
    /// Remote deletes, the changed-metadata delta, membership.
    case reconcile
  }

  /// One row per stage, so a stage keeps its identity across progress updates
  /// and the list doesn't re-animate on every page.
  public var id: Stage { stage }

  public var stage: Stage
  /// The saved view currently being worked on, where the stage proceeds view by
  /// view. `nil` for the default list and for stages with no such subdivision.
  public var detail: String?
  public var completed: Int
  /// `nil` while the total isn't known yet — the UI shows an indeterminate bar
  /// rather than a wrong one.
  public var total: Int?

  public init(stage: Stage, detail: String? = nil, completed: Int = 0, total: Int? = nil) {
    self.stage = stage
    self.detail = detail
    self.completed = completed
    self.total = total
  }

  /// `0...1`, or `nil` when the total is unknown or degenerate.
  public var fraction: Double? {
    guard let total, total > 0 else { return nil }
    return min(1, Double(completed) / Double(total))
  }
}

/// How a cache sweep tells the store what it is doing. `nil` means "finished".
/// Main-actor because both ends are: `CachingBackend` and `DocumentStore`.
public typealias SyncProgressReporter = @MainActor (SyncActivity?) -> Void

extension Collection<SyncActivity> {
  /// Every running stage, in a **fixed** order.
  ///
  /// Fixed rather than by recency or start time: the stages genuinely overlap —
  /// `sync()` kicks the reconcile off in its own task and returns, so a
  /// reconcile is usually still going when the library fill starts — and a list
  /// that reorders itself as each one reports progress is unreadable.
  public var sortedForDisplay: [SyncActivity] {
    let order = Dictionary(
      uniqueKeysWithValues: SyncActivity.Stage.allCases.enumerated().map { ($1, $0) })
    return sorted { (order[$0.stage] ?? 0) < (order[$1.stage] ?? 0) }
  }
}
