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
      hasRows: true, isFetching: false, totalCount: 900, isCacheComplete: false,
      fillFailed: stoppedShort)
    #expect(partial.isIncomplete)
    // An empty prefix with a positive total is unavailable, not loading forever.
    let empty = DocumentListState(
      hasRows: false, isFetching: false, totalCount: 900, isCacheComplete: false,
      fillFailed: stoppedShort)
    #expect(empty.content == .unavailable)
    // While the replacement still runs, the list counts as fetching.
    let following = DocumentListState(
      hasRows: false, isFetching: true, totalCount: 900, isCacheComplete: false,
      fillFailed: false)
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
}
