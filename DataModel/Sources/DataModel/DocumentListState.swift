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
  ///   - isFetching: A fill *the list itself started* is pending or in flight.
  ///   - isFillTakenOver: Another fill owns the observed query — it drained the
  ///     list's — and the list is waiting on it (see
  ///     ``DocumentListFillTracking``). Kept apart from `isFetching` because the
  ///     list isn't the one fetching, and folded in *here* rather than at the
  ///     call site so "something is still filling this query" can't be dropped
  ///     on the way in: an empty cache under a running fill is an absence of
  ///     data, not an absence of matches.
  ///   - totalCount: The server's total as last recorded for the query.
  ///   - isCacheComplete: A fill has paged the query to the end and nothing has
  ///     truncated it since.
  ///   - fillFailed: The list's most recent fill for this query failed, at page
  ///     1 or while paging the rest — or another fill took the query over and
  ///     ended without completing it (see ``DocumentListFillTracking``).
  public init(
    hasRows: Bool, isFetching: Bool, isFillTakenOver: Bool, totalCount: UInt?,
    isCacheComplete: Bool, fillFailed: Bool
  ) {
    let isBeingFilled = isFetching || isFillTakenOver

    if hasRows {
      content = .documents
      // Hidden while a retry runs, so the retry visibly does something; it
      // comes back if that attempt fails too.
      isIncomplete = fillFailed && !isCacheComplete && !isBeingFilled
      return
    }

    isIncomplete = false
    if isBeingFilled {
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
///
/// Both legs of a fill end this way and are judged by the same rule: the
/// awaited page 1 and the background paging behind it. A takeover that lands
/// while page 1 is still in flight leaves the list nothing at all — no rows, no
/// fetch, no failure — which is the one combination that reads as a real
/// zero-match answer, so it has to be followed just like the other.
public enum DocumentListFillTracking {
  /// How the tracked fill's leg ended.
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

  /// Whether the list on screen should re-sync its membership on a new mark.
  ///
  /// Not for a mark already there when the list subscribed: opening a list
  /// fills it anyway. Not while the window is widened past the first page,
  /// where the rewrite could leave the user looking at placeholders; the next
  /// refresh picks it up.
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

  /// After waiting out the query's writers, whether the list still has to
  /// re-sync itself: one of them may have rewritten the whole order meanwhile.
  public static func resyncsMembershipAfterWriters(isStale: Bool, isWidened: Bool) -> Bool {
    isStale && !isWidened
  }
}
