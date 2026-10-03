//
//  DocumentListFillTrackingTests.swift
//  DataModel
//

import Testing

@testable import DataModel

@Suite
struct DocumentListFillTrackingTests {
  @Test("A fill the list still tracks reports its own outcome")
  func currentFillOutcome() {
    #expect(DocumentListFillTracking.followUp(after: .finished, isCurrent: true) == .none)
    #expect(DocumentListFillTracking.followUp(after: .failed, isCurrent: true) == .recordFailure)
  }

  @Test(
    "A fill cancelled by something other than the list is followed, not dropped",
    .bug("https://github.com/paulgessinger/swift-paperless/pull/723"))
  func displacedFillIsFollowed() {
    #expect(
      DocumentListFillTracking.followUp(after: .cancelled, isCurrent: true) == .followReplacement)
  }

  @Test("A fill the list moved on from reports nothing, however it ended")
  func supersededFillIsIgnored() {
    for end in [DocumentListFillTracking.End.finished, .failed, .cancelled] {
      #expect(DocumentListFillTracking.followUp(after: end, isCurrent: false) == .none)
    }
  }

  @Test("A replacement that left the cache incomplete stopped short")
  func replacementOutcome() {
    #expect(DocumentListFillTracking.replacementStoppedShort(isCacheComplete: false))
    #expect(!DocumentListFillTracking.replacementStoppedShort(isCacheComplete: true))
  }

  @Test(
    "A replacement that stopped short reaches the list as a failed load",
    .bug("https://github.com/paulgessinger/swift-paperless/pull/723"))
  func replacementStoppedShortShowsInList() {
    let stoppedShort = DocumentListFillTracking.replacementStoppedShort(isCacheComplete: false)
    // Partial rows get the incomplete notice.
    let partial = DocumentListState(
      hasRows: true, isFetching: false, isFillTakenOver: false, totalCount: 900,
      isCacheComplete: false, fillFailed: stoppedShort)
    #expect(partial.isIncomplete)
    // An empty prefix with a positive total is unavailable, not loading forever.
    let empty = DocumentListState(
      hasRows: false, isFetching: false, isFillTakenOver: false, totalCount: 900,
      isCacheComplete: false, fillFailed: stoppedShort)
    #expect(empty.content == .unavailable)
    // While the replacement still runs, the list counts as fetching.
    let following = DocumentListState(
      hasRows: false, isFetching: true, isFillTakenOver: false, totalCount: 900,
      isCacheComplete: false, fillFailed: false)
    #expect(following.content == .loading)
  }

  @Test(
    "The list re-syncs its membership when its order flips to stale",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/689"))
  func staleFlipResyncs() {
    #expect(
      DocumentListFillTracking.resyncsMembershipForStaleOrder(
        wasStale: false, isStale: true, isNewMark: true, isWidened: false))
  }

  @Test(
    "A new mark on an order that is still stale re-syncs again",
    .bug("https://github.com/paulgessinger/swift-paperless/pull/742"))
  func remarkResyncs() {
    #expect(
      DocumentListFillTracking.resyncsMembershipForStaleOrder(
        wasStale: true, isStale: true, isNewMark: true, isWidened: false))
  }

  @Test("A flag already set when the list subscribed is left to the list's own fill")
  func initialStaleIsLeftToFill() {
    #expect(
      !DocumentListFillTracking.resyncsMembershipForStaleOrder(
        wasStale: nil, isStale: true, isNewMark: false, isWidened: false))
  }

  @Test("A status that brings no new mark doesn't re-sync")
  func noNewMark() {
    #expect(
      !DocumentListFillTracking.resyncsMembershipForStaleOrder(
        wasStale: true, isStale: true, isNewMark: false, isWidened: false))
    #expect(
      !DocumentListFillTracking.resyncsMembershipForStaleOrder(
        wasStale: true, isStale: false, isNewMark: false, isWidened: false))
    #expect(
      !DocumentListFillTracking.resyncsMembershipForStaleOrder(
        wasStale: false, isStale: false, isNewMark: false, isWidened: false))
  }

  @Test("A list scrolled past its first page isn't rewritten from under the user")
  func widenedListWaits() {
    #expect(
      !DocumentListFillTracking.resyncsMembershipForStaleOrder(
        wasStale: false, isStale: true, isNewMark: true, isWidened: true))
    #expect(
      !DocumentListFillTracking.resyncsMembershipForStaleOrder(
        wasStale: true, isStale: true, isNewMark: true, isWidened: true))
    #expect(
      !DocumentListFillTracking.resyncsMembershipAfterWriters(isStale: true, isWidened: true))
  }

  @Test("After the query's writers finish, the list rewrites only if nothing cleared the flag")
  func afterWriters() {
    #expect(
      DocumentListFillTracking.resyncsMembershipAfterWriters(isStale: true, isWidened: false))
    #expect(
      !DocumentListFillTracking.resyncsMembershipAfterWriters(isStale: false, isWidened: false))
  }

  @Test("A page-1 fill is judged by the same rule as the paging behind it")
  func pageOneEndsLikeTheBackgroundLeg() {
    // The list awaits page 1 and pages the rest in the background, but a
    // takeover can land during either, and both have to be followed.
    #expect(DocumentListFillTracking.followUp(after: .failed, isCurrent: true) == .recordFailure)
    #expect(
      DocumentListFillTracking.followUp(after: .cancelled, isCurrent: true) == .followReplacement)
    #expect(DocumentListFillTracking.followUp(after: .cancelled, isCurrent: false) == .none)
  }

  @Test(
    "A page-1 fill drained on a cold launch shows placeholders, never 'No documents'",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/692", id: 692))
  func drainedPageOneIsNotAnEmptyResult() {
    // Nothing cached, nothing fetched, no error: everything the list knows
    // after its page-1 fill was drained before writing a row.
    func coldCache(isFillTakenOver: Bool, fillFailed: Bool = false) -> DocumentListState {
      DocumentListState(
        hasRows: false, isFetching: false, isFillTakenOver: isFillTakenOver, totalCount: nil,
        isCacheComplete: false, fillFailed: fillFailed)
    }

    // Unfollowed, this is the cold-launch flash.
    #expect(coldCache(isFillTakenOver: false).content == .empty)

    // Followed, the list waits on whoever took the query over.
    let following =
      DocumentListFillTracking.followUp(after: .cancelled, isCurrent: true) == .followReplacement
    #expect(coldCache(isFillTakenOver: following).content == .loading)
  }

  @Test(
    "Following a drained page-1 fill resolves on every exit, including failure",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/692", id: 692))
  func followedPageOneAlwaysResolves() {
    // The replacement died too (an offline cold launch kills both fills): the
    // list has to offer a retry, not spin forever. This is why `.unavailable`
    // exists.
    let bothFailed = DocumentListState(
      hasRows: false, isFetching: false, isFillTakenOver: false, totalCount: nil,
      isCacheComplete: false,
      fillFailed: DocumentListFillTracking.replacementStoppedShort(isCacheComplete: false))
    #expect(bothFailed.content == .unavailable)

    // The replacement finished against a server that really has no documents:
    // the takeover must not mask a genuine zero-match answer.
    let genuinelyEmpty = DocumentListState(
      hasRows: false, isFetching: false, isFillTakenOver: false, totalCount: 0,
      isCacheComplete: true,
      fillFailed: DocumentListFillTracking.replacementStoppedShort(isCacheComplete: true))
    #expect(genuinelyEmpty.content == .empty)

    // The replacement finished and the rows are on their way: still no flash in
    // the beat before the observation repaints.
    let rowsIncoming = DocumentListState(
      hasRows: false, isFetching: false, isFillTakenOver: false, totalCount: 12,
      isCacheComplete: true,
      fillFailed: DocumentListFillTracking.replacementStoppedShort(isCacheComplete: true))
    #expect(rowsIncoming.content == .loading)
  }
}
