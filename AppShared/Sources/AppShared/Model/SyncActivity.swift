//
//  SyncActivity.swift
//  AppShared
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
public struct SyncActivity: Sendable, Equatable {
  public enum Stage: Sendable, Equatable {
    /// Tags, correspondents, saved views… — the element collections.
    case elementSync
    /// Paging saved views and the default list into `query_order`.
    case libraryFill
    /// Per-document notes and file metadata.
    case detailFill
    /// Remote deletes, the changed-metadata delta, membership.
    case reconcile
  }

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

  /// Which stage to show when several are running at once.
  ///
  /// They genuinely overlap: `sync()` kicks the reconcile off in its own task
  /// and returns, so a reconcile is usually still going when the library fill
  /// starts. Highest wins — the heaviest, longest-running work is the most
  /// informative thing to name.
  fileprivate var displayPriority: Int {
    switch stage {
    case .libraryFill: 3
    case .detailFill: 2
    case .reconcile: 1
    case .elementSync: 0
    }
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
  /// The stage to display when several overlap, or `nil` when nothing is running.
  public var mostSignificant: SyncActivity? {
    self.max { $0.displayPriority < $1.displayPriority }
  }
}
