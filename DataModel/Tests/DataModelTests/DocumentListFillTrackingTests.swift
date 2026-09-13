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
}
