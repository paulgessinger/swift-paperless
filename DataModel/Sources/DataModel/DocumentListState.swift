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
  ///     1 or while paging the rest.
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
