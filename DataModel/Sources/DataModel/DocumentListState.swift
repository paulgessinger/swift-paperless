//
//  DocumentListState.swift
//  DataModel
//
//  What the document list shows for the query it observes, derived from the
//  cache (rows, total, completeness) and the outcome of the list's own fill.
//  Kept free of UI and storage types so the decision — in particular "a failed
//  load must never read as zero matches" — is testable on the host.
//

/// Which list the user is looking at, for wording a failure accurately.
public enum DocumentListScope: Equatable, Sendable {
  /// The default document list: no saved view and no filter or custom sort.
  case allDocuments
  /// An unmodified saved view.
  case savedView(id: UInt)
  /// Anything else: an ad-hoc filter, or a saved view the user has since
  /// edited (its query is no longer the saved view's).
  case filtered

  /// - Parameters:
  ///   - savedView: The saved view the filter was built from, if any.
  ///   - modified: Whether the filter was edited after being built.
  ///   - filtering: Whether the filter narrows or re-sorts the default list.
  public init(savedView: UInt?, modified: Bool, filtering: Bool) {
    if let savedView, !modified {
      self = .savedView(id: savedView)
    } else if filtering {
      self = .filtered
    } else {
      self = .allDocuments
    }
  }
}

public struct DocumentListState: Equatable, Sendable {
  public enum Content: Equatable, Sendable {
    /// Rows are on their way: show placeholders.
    case loading
    /// The query answered with no documents: the normal empty state.
    case empty
    /// Nothing to show *because loading failed*: an error state with a retry,
    /// never the empty state.
    case unavailable
    /// Show the rows.
    case documents
  }

  public var content: Content

  /// Rows are shown, but the list's fill failed before the cache held the whole
  /// query, so what is on screen is known to be a truncated answer.
  public var isIncomplete: Bool

  /// - Parameters:
  ///   - hasRows: The observed cache prefix is non-empty.
  ///   - isFetching: A fill for the observed query is pending or in flight.
  ///   - totalCount: The server's total as last recorded for the query.
  ///   - isCacheComplete: A fill has paged the query to the end and nothing has
  ///     truncated it since.
  ///   - fillFailed: The list's most recent fill for this query failed, at page
  ///     1 or while paging the rest — or another fill took the query over and
  ///     ended without completing it (see ``DocumentListFillTracking``).
  public init(
    hasRows: Bool, isFetching: Bool, totalCount: UInt?, isCacheComplete: Bool, fillFailed: Bool
  ) {
    if hasRows {
      content = .documents
      // Hidden while a retry runs, so the retry visibly does something; it
      // comes back if that attempt fails too.
      isIncomplete = fillFailed && !isCacheComplete && !isFetching
      return
    }

    isIncomplete = false
    if isFetching {
      content = .loading
    } else if fillFailed {
      // An empty *complete* cache is a real zero-match answer from an earlier
      // fill; anything else is an absence of data, not an absence of matches.
      content = isCacheComplete && (totalCount ?? 0) == 0 ? .empty : .unavailable
    } else if (totalCount ?? 0) > 0 {
      // The fill has reported a total but the rows haven't been observed yet:
      // don't flash "No documents" in that beat.
      content = .loading
    } else {
      content = .empty
    }
  }
}

/// What the list does when the fill it tracks for the query on screen ends.
///
/// The list can't simply ignore a cancelled fill. Only one fill writes a query
/// at a time, so when another one starts on the same query (the proactive
/// library sweep over the default list or a saved view, say) it cancels the
/// list's. That newer fill now decides whether the cache ends up whole, and
/// the list never gets its handle. Dropping the cancellation left the list
/// with no outcome at all: partial rows without the incomplete notice, or
/// placeholders forever over an empty prefix.
public enum DocumentListFillTracking {
  /// How the tracked fill's background paging ended.
  public enum End: Equatable, Sendable {
    /// Paged to the end of the query.
    case finished
    /// Stopped with an error.
    case failed
    /// Cancelled: by the list itself, or by a fill that took the query over.
    case cancelled
  }

  public enum FollowUp: Equatable, Sendable {
    /// Nothing to report.
    case none
    /// Record the error as the list's fill failure.
    case recordFailure
    /// Wait for whatever took the query over, then judge the cache.
    case followReplacement
  }

  /// - Parameters:
  ///   - end: How the fill ended.
  ///   - isCurrent: The list still tracks this fill. `false` once the list
  ///     itself moved on (a newer fill of its own, a query switch, a teardown),
  ///     which is also every cancellation the list caused.
  public static func followUp(after end: End, isCurrent: Bool) -> FollowUp {
    guard isCurrent else { return .none }
    switch end {
    case .finished: return .none
    case .failed: return .recordFailure
    // The list didn't cancel it, so another fill did.
    case .cancelled: return .followReplacement
    }
  }

  /// Once nothing owns the query any more, whether the fill that replaced the
  /// list's stopped short. Judged from the cache because the replacement's
  /// error isn't the list's to see; a cache that isn't complete with nobody
  /// filling it is a truncated answer however it came about.
  public static func replacementStoppedShort(isCacheComplete: Bool) -> Bool {
    !isCacheComplete
  }

  /// Whether the list on screen should re-sync its query's membership because
  /// the cached order was just marked stale — a changed-documents delta or an
  /// edit moved a document the order lists, so it may now sit in the wrong
  /// place or not belong at all.
  ///
  /// On every new mark the list sees: the flip to stale, and a further mark on
  /// an order that is already stale. The second matters because a flag that
  /// stayed set means nothing has re-synced the list yet — a re-sync failed
  /// offline, or a mark landed while one was in flight — and without it the
  /// list would wait for a manual refresh.
  ///
  /// Not on a flag already set when the list subscribed: opening or switching
  /// to a list already fills it, and a fill's first page is what clears the
  /// flag.
  ///
  /// Not while the list's window has been widened past the first page. The
  /// rewrite replaces the whole order in one write, and the cache has objects
  /// behind at most the pages that were fetched, so a user scrolled further
  /// down could be left looking at placeholders. The flag stays set and the
  /// next refresh (pull, reopen, filter change) picks it up.
  ///
  /// - Parameters:
  ///   - wasStale: The flag's previous value, or `nil` for the first status
  ///     the list observed for this query.
  ///   - isStale: The flag's value now.
  ///   - isNewMark: The order was marked since the previous status.
  ///   - isWidened: The list observes more rows than a fill's first page
  ///     writes.
  public static func resyncsMembershipForStaleOrder(
    wasStale: Bool?, isStale: Bool, isNewMark: Bool, isWidened: Bool
  ) -> Bool {
    guard let wasStale, isStale, !isWidened else { return false }
    return !wasStale || isNewMark
  }

  /// After waiting out whoever was writing the query when it went stale,
  /// whether the list still has to re-sync the membership itself.
  ///
  /// A whole-order rewrite in the meantime (the membership sweep, or a fill
  /// whose first page landed after the change) has already cleared the flag.
  /// A fill that was past its first page has not: its later pages keep the
  /// flag, since they never revisit the rows it is about.
  public static func resyncsMembershipAfterWriters(isStale: Bool, isWidened: Bool) -> Bool {
    isStale && !isWidened
  }
}
