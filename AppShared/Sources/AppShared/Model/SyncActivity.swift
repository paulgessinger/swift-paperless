//
//  SyncActivity.swift
//  AppShared
//

import Foundation

/// What the offline sync is doing right now, for the Offline & Sync screen.
///
/// The screen used to infer this from two booleans (`isFillingLibrary`,
/// `isRefreshing`), which could only ever say "something is happening". That is
/// not enough for a pass with no cap on it: a first cold fill of a large library
/// runs for a long time and the user needs to see it moving, and which stage it
/// is in, rather than a spinner that might equally be stuck.
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

  /// `0...1`, or `nil` when the total is unknown or degenerate.
  public var fraction: Double? {
    guard let total, total > 0 else { return nil }
    return min(1, Double(completed) / Double(total))
  }
}

/// How a cache sweep tells the store what it is doing. `nil` means "finished".
/// Main-actor because both ends are: `CachingBackend` and `DocumentStore`.
public typealias SyncProgressReporter = @MainActor (SyncActivity?) -> Void
