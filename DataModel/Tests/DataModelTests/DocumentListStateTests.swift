//
//  DocumentListStateTests.swift
//  DataModel
//

import Testing

@testable import DataModel

@Suite
struct DocumentListStateTests {
  private func state(
    hasRows: Bool = false, isFetching: Bool = false, totalCount: UInt? = nil,
    isCacheComplete: Bool = false, fillFailed: Bool = false
  ) -> DocumentListState {
    DocumentListState(
      hasRows: hasRows, isFetching: isFetching, totalCount: totalCount,
      isCacheComplete: isCacheComplete, fillFailed: fillFailed)
  }

  @Test(
    "A failed fill over an empty cache is unavailable, not an empty result",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/692", id: 692),
    .bug("https://github.com/paulgessinger/swift-paperless/issues/672", id: 672))
  func failedFillWithoutCacheIsUnavailable() {
    #expect(state(fillFailed: true).content == .unavailable)
    // A total recorded by an earlier, truncated fill doesn't make it loading.
    #expect(state(totalCount: 40, fillFailed: true).content == .unavailable)
    // A complete cache that has since lost its rows still has nothing to show.
    #expect(state(totalCount: 40, isCacheComplete: true, fillFailed: true).content == .unavailable)
  }

  @Test("A successful query with no matches shows the normal empty state")
  func zeroMatchesIsEmpty() {
    #expect(state(totalCount: 0).content == .empty)
    #expect(state(totalCount: 0, isCacheComplete: true).content == .empty)
    // A complete zero-match answer cached earlier stays a real answer offline.
    #expect(state(totalCount: 0, isCacheComplete: true, fillFailed: true).content == .empty)
  }

  @Test("Placeholders while a fill runs or its rows haven't been observed yet")
  func loading() {
    #expect(state(isFetching: true).content == .loading)
    // A retry after a failure shows progress rather than the stale error.
    #expect(state(isFetching: true, fillFailed: true).content == .loading)
    #expect(state(totalCount: 12).content == .loading)
  }

  @Test(
    "Rows from a truncated cache are flagged incomplete when the fill failed",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/692", id: 692))
  func partialCacheIsIncomplete() {
    let partial = state(hasRows: true, totalCount: 900, fillFailed: true)
    #expect(partial.content == .documents)
    #expect(partial.isIncomplete)
  }

  @Test("Rows are not flagged when nothing is known to be missing")
  func completeOrHealthyRowsAreNotFlagged() {
    // Offline over a complete cache: the answer on screen is whole.
    #expect(!state(hasRows: true, isCacheComplete: true, fillFailed: true).isIncomplete)
    // Still paging in the background: incomplete, but not failed.
    #expect(!state(hasRows: true, totalCount: 900).isIncomplete)
    // A retry in flight hides the notice until it has an outcome.
    #expect(!state(hasRows: true, isFetching: true, fillFailed: true).isIncomplete)
  }

  @Test("Scope distinguishes the default list, a saved view and an ad-hoc filter")
  func scope() {
    #expect(DocumentListScope(savedView: nil, modified: false, filtering: false) == .allDocuments)
    #expect(DocumentListScope(savedView: 3, modified: false, filtering: true) == .savedView(id: 3))
    // A saved view without rules is still that saved view.
    #expect(DocumentListScope(savedView: 3, modified: false, filtering: false) == .savedView(id: 3))
    #expect(DocumentListScope(savedView: nil, modified: true, filtering: true) == .filtered)
    // An edited saved view no longer runs the saved view's query.
    #expect(DocumentListScope(savedView: 3, modified: true, filtering: true) == .filtered)
    #expect(DocumentListScope(savedView: 3, modified: true, filtering: false) == .allDocuments)
  }
}
