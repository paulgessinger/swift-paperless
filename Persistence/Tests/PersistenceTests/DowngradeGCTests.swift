import Common
import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

@Suite("DowngradeGC")
struct DowngradeGCTests {
  // MARK: - Helpers

  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func doc(_ id: UInt, _ title: String, versions: [DocumentVersion] = []) -> Document {
    Document(
      id: id, title: title, created: date(1000), tags: [],
      owner: .user(1), versions: versions)
  }

  private func note(_ id: UInt) -> DocumentNote {
    DocumentNote(id: id, note: "note-\(id)", created: date(1000), user: nil)
  }

  private func metadata(_ checksum: String) -> Metadata {
    Metadata(
      originalChecksum: checksum, originalSize: 1, originalMimeType: "application/pdf",
      mediaFilename: "scan.pdf", hasArchiveVersion: false, originalMetadata: [],
      originalFilename: "scan.pdf", lang: "en")
  }

  private func database(_ server: UUID) throws -> Persistence.Database {
    try Database.seeded(serverID: server)
  }

  // MARK: - Document rows

  @Test("reclaimAfterDowngrade keeps every document row and its detail")
  func reclaimKeepsDocumentRows() async throws {
    let server = UUID()
    let database = try database(server)
    let keep = QueryKey(sentinel: "default")
    let drop = QueryKey(sentinel: "saved-view")

    try await database.upsertDocuments([doc(1, "A"), doc(2, "B"), doc(3, "C")], serverID: server)
    try await database.replaceQueryOrder(
      queryKey: keep, serverID: server, orderedIDs: [1, 2], basis: .initial)
    // 3 is listed only by the saved view the downgrade drops.
    try await database.replaceQueryOrder(
      queryKey: drop, serverID: server, orderedIDs: [3], basis: .initial)
    try await database.setNotes([note(1)], serverID: server, documentID: 3)
    try await database.setFileMetadata(
      metadata("sum"), serverID: server, versionID: 3, documentModified: nil)

    try await database.reclaimAfterDowngrade(
      serverID: server, defaultQueryKey: keep, keepingFirst: 1)

    #expect(try await database.documentCount(serverID: server) == 3)
    #expect(try await database.notes(serverID: server, documentID: 3)?.count == 1)
    #expect(try await database.fileMetadata(serverID: server, versionID: 3) != nil)
  }

  // MARK: - dropQueryOrder

  @Test("dropQueryOrder removes every other query's order/meta/sync-error, keeps the given one")
  func dropQueryOrderKeepsOnlyGivenKey() async throws {
    let server = UUID()
    let database = try database(server)
    let keep = QueryKey(sentinel: "default")
    let drop = QueryKey(sentinel: "saved-view")

    try await database.upsertDocuments([doc(1, "A"), doc(2, "B")], serverID: server)
    try await database.replaceQueryOrder(
      queryKey: keep, serverID: server, orderedIDs: [1, 2], basis: .initial)
    try await database.replaceQueryOrder(
      queryKey: drop, serverID: server, orderedIDs: [1, 2], basis: .initial)
    try await database.recordQuerySyncError(
      serverID: server, queryKey: drop.rawValue, savedViewName: "Saved", message: "boom")

    try await database.dropQueryOrder(serverID: server, exceptQueryKey: keep)

    #expect(
      try await database.queryDocuments(queryKey: keep, serverID: server, limit: 10).map(\.id) == [
        1, 2,
      ])
    #expect(try await database.queryDocuments(queryKey: drop, serverID: server, limit: 10).isEmpty)
    // query_meta gone too: totalCount reads nil, not just localCount == 0.
    #expect(try await database.queryStatus(queryKey: drop, serverID: server).totalCount == nil)
    #expect(try await database.queryStatus(queryKey: keep, serverID: server).totalCount == 2)
  }

  // MARK: - truncateQueryOrder

  @Test("truncateQueryOrder keeps only the first N positions")
  func truncateKeepsPrefix() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "default")

    try await database.upsertDocuments((1...5).map { doc($0, "d\($0)") }, serverID: server)
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [1, 2, 3, 4, 5], basis: .initial)

    try await database.truncateQueryOrder(serverID: server, queryKey: key, keepingFirst: 3)

    #expect(
      try await database.queryDocuments(queryKey: key, serverID: server, limit: 10).map(\.id) == [
        1, 2, 3,
      ])
    // The server's true total is untouched by the local cap.
    #expect(try await database.queryStatus(queryKey: key, serverID: server).totalCount == 5)
  }

  @Test("truncateQueryOrder counts rows, not position values, when positions are gappy")
  func truncateCountsRowsNotPositions() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "default")

    try await database.upsertDocuments((1...5).map { doc($0, "d\($0)") }, serverID: server)
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [1, 2, 3, 4, 5], basis: .initial)
    // Punch a hole the way a page-boundary repeat or a remote delete does: the
    // surviving rows now sit at positions 0, 2, 3, 4 rather than 0...3.
    try await database.deleteDocuments(serverID: server, removedIDs: [2])

    try await database.truncateQueryOrder(serverID: server, queryKey: key, keepingFirst: 3)

    // Three rows kept. A `position < 3` test would have kept only two (0 and 2).
    #expect(
      try await database.queryDocuments(queryKey: key, serverID: server, limit: 10).map(\.id) == [
        1, 3, 4,
      ])
  }

  @Test(
    "A truncated query is no longer complete, though it keeps its fill stamp",
    .bug("https://github.com/paulgessinger/swift-paperless/pull/723"))
  func truncatedQueryIsIncomplete() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "default")

    try await database.replaceQueryPage(
      queryKey: key, serverID: server, documents: (1...5).map { doc($0, "d\($0)") },
      totalCount: 5, basis: .initial)
    try await database.markQueryFillComplete(queryKey: key, serverID: server)
    #expect(try await database.queryStatus(queryKey: key, serverID: server).isComplete)

    try await database.truncateQueryOrder(serverID: server, queryKey: key, keepingFirst: 3)

    let status = try await database.queryStatus(queryKey: key, serverID: server)
    #expect(status.isComplete == false)
    #expect(status.totalCount == 5)
    // The stamp survives on purpose: the reachability LRU ranks on it.
    #expect(try await database.queryFillCompletedAt(queryKey: key, serverID: server) != nil)
  }

  @Test("reclaimAfterDowngrade leaves the capped default list incomplete")
  func reclaimLeavesDefaultListIncomplete() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "default")

    try await database.replaceQueryPage(
      queryKey: key, serverID: server, documents: (1...4).map { doc($0, "d\($0)") },
      totalCount: 4, basis: .initial)
    try await database.markQueryFillComplete(queryKey: key, serverID: server)

    try await database.reclaimAfterDowngrade(
      serverID: server, defaultQueryKey: key, keepingFirst: 2)

    #expect(try await database.queryStatus(queryKey: key, serverID: server).isComplete == false)
    // A cap at or above the list's size cuts nothing, so it stays complete.
    let whole = QueryKey(sentinel: "whole")
    try await database.replaceQueryPage(
      queryKey: whole, serverID: server, documents: [doc(1, "d1"), doc(2, "d2")],
      totalCount: 2, basis: .initial)
    try await database.markQueryFillComplete(queryKey: whole, serverID: server)
    try await database.truncateQueryOrder(serverID: server, queryKey: whole, keepingFirst: 200)
    #expect(try await database.queryStatus(queryKey: whole, serverID: server).isComplete)
  }

  @Test("A complete fill with position gaps still reads complete")
  func gappyCompleteFillIsComplete() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "default")

    // Document 3 repeats across the page boundary: the unique key skips the
    // repeat, so five server results leave four rows at positions 0, 1, 2, 4.
    try await database.replaceQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "a"), doc(2, "b"), doc(3, "c")],
      totalCount: 5, basis: .initial)
    try await database.appendQueryPage(
      queryKey: key, serverID: server, documents: [doc(3, "c"), doc(4, "d")],
      startPosition: 3, totalCount: 5)
    try await database.markQueryFillComplete(queryKey: key, serverID: server)

    var status = try await database.queryStatus(queryKey: key, serverID: server)
    #expect(status.localCount == 4)
    #expect(status.isComplete)

    // A remote delete mid-list punches another hole; the order is still whole.
    try await database.deleteDocuments(serverID: server, removedIDs: [2])
    status = try await database.queryStatus(queryKey: key, serverID: server)
    #expect(status.localCount == 3)
    #expect(status.isComplete)
  }

  @Test("Completeness needs the stamp; a missing total leaves the stamp to decide")
  func orderCompletenessRule() {
    let stamp = date(1)
    #expect(!Database.isOrderComplete(filledAt: nil, lastPosition: 4, totalCount: 5))
    #expect(Database.isOrderComplete(filledAt: stamp, lastPosition: 4, totalCount: 5))
    #expect(!Database.isOrderComplete(filledAt: stamp, lastPosition: 2, totalCount: 5))
    // More positions than the server's total (the total shrank mid-fill).
    #expect(Database.isOrderComplete(filledAt: stamp, lastPosition: 9, totalCount: 5))
    // A complete zero-match answer.
    #expect(Database.isOrderComplete(filledAt: stamp, lastPosition: nil, totalCount: 0))
    // Every row cut, with a non-zero total.
    #expect(!Database.isOrderComplete(filledAt: stamp, lastPosition: nil, totalCount: 3))
    #expect(Database.isOrderComplete(filledAt: stamp, lastPosition: nil, totalCount: nil))
  }

  // MARK: - reclaimAfterDowngrade

  @Test("reclaimAfterDowngrade drops and truncates the lists in one call")
  func reclaimDoesTheWholeSequence() async throws {
    let server = UUID()
    let database = try database(server)
    let keep = QueryKey(sentinel: "default")
    let drop = QueryKey(sentinel: "saved-view")

    try await database.upsertDocuments((1...6).map { doc($0, "d\($0)") }, serverID: server)
    try await database.replaceQueryOrder(
      queryKey: keep, serverID: server, orderedIDs: [1, 2, 3, 4], basis: .initial)
    // 5 and 6 are only reachable through the saved view.
    try await database.replaceQueryOrder(
      queryKey: drop, serverID: server, orderedIDs: [5, 6], basis: .initial)

    let removed = try await database.reclaimAfterDowngrade(
      serverID: server, defaultQueryKey: keep, keepingFirst: 2)

    // The saved view's two rows, and 3 and 4 off the truncated prefix.
    #expect(removed == 4)
    #expect(
      try await database.queryDocuments(queryKey: keep, serverID: server, limit: 10).map(\.id) == [
        1, 2,
      ])
    #expect(try await database.queryDocuments(queryKey: drop, serverID: server, limit: 10).isEmpty)
    #expect(try await database.documentCount(serverID: server) == 6)
  }

  @Test("reclaimAfterDowngrade clears the library-coverage marker")
  func reclaimClearsCoverageMarker() async throws {
    let server = UUID()
    let database = try database(server)
    let keep = QueryKey(sentinel: "default")

    try await database.upsertDocuments([doc(1, "A")], serverID: server)
    try await database.replaceQueryOrder(
      queryKey: keep, serverID: server, orderedIDs: [1], basis: .initial)
    try await database.setLibraryCoverageAt(date(5000), serverID: server)

    try await database.reclaimAfterDowngrade(
      serverID: server, defaultQueryKey: keep, keepingFirst: 200)

    // The cache no longer matches what the marker claimed, so a later
    // re-upgrade has to re-fill instead of reading a fresh stamp.
    #expect(try await database.libraryCoverageAt(serverID: server) == nil)
  }

  @Test("reclaimAfterDowngrade leaves the delta watermark alone")
  func reclaimKeepsDeltaWatermark() async throws {
    let server = UUID()
    let database = try database(server)
    let keep = QueryKey(sentinel: "default")

    try await database.upsertDocuments([doc(1, "A")], serverID: server)
    try await database.replaceQueryOrder(
      queryKey: keep, serverID: server, orderedIDs: [1], basis: .initial)
    try await database.setDeltaWatermark(date(7000), serverID: server)
    try await database.setLibraryCoverageAt(date(5000), serverID: server)

    try await database.reclaimAfterDowngrade(
      serverID: server, defaultQueryKey: keep, keepingFirst: 200)

    // Documents that survive the reclaim still want their changes applied, so
    // the delta must not re-baseline over them.
    #expect(try await database.deltaWatermark(serverID: server) == date(7000))
  }

  // MARK: - Kept offline

  @Test("a kept document stays kept through the downgrade, with its notes")
  func keptDocumentSurvives() async throws {
    let server = UUID()
    let database = try database(server)
    let keep = QueryKey(sentinel: "default")
    let drop = QueryKey(sentinel: "saved-view")

    try await database.upsertDocuments([doc(1, "A"), doc(2, "B"), doc(3, "C")], serverID: server)
    try await database.replaceQueryOrder(
      queryKey: keep, serverID: server, orderedIDs: [1], basis: .initial)
    try await database.replaceQueryOrder(
      queryKey: drop, serverID: server, orderedIDs: [2, 3], basis: .initial)
    try await database.setNotes([note(1)], serverID: server, documentID: 2)
    try await database.setKeptOffline(serverID: server, documentID: 2, kept: true)

    let removed = try await database.reclaimAfterDowngrade(
      serverID: server, defaultQueryKey: keep, keepingFirst: 200)

    #expect(removed == 2)
    #expect(try await database.document(serverID: server, id: 2) != nil)
    #expect(try await database.notes(serverID: server, documentID: 2)?.count == 1)
    #expect(try await database.keptOfflineIDs(serverID: server) == [2])
  }

  @Test("a kept view's members keep their rows and archives through the downgrade")
  func keptViewMembersSurvive() async throws {
    let server = UUID()
    let database = try database(server)
    let keep = QueryKey(sentinel: "default")
    let view = QueryKey(sentinel: "saved-view")

    try await database.upsertDocuments([doc(1, "A"), doc(2, "B"), doc(3, "C")], serverID: server)
    try await database.replaceQueryOrder(
      queryKey: keep, serverID: server, orderedIDs: [1], basis: .initial)
    try await database.replaceQueryOrder(
      queryKey: view, serverID: server, orderedIDs: [2, 3], basis: .initial)
    try await database.keepOfflineView(serverID: server, savedViewID: 7)
    try await database.replaceKeptOfflineViewMembers(
      serverID: server, savedViewID: 7, documentIDs: [2])
    for id: UInt in [1, 2, 3] {
      try await database.recordFile(
        ContentStore.Key(serverID: server, versionID: id, kind: .archive), documentID: id,
        size: 10, modified: nil, checksum: nil, storedAt: date(1), lastAccessedAt: nil)
    }

    try await database.reclaimAfterDowngrade(
      serverID: server, defaultQueryKey: keep, keepingFirst: 200)

    #expect(try await database.documentCount(serverID: server) == 3)
    #expect(try await database.isKept(serverID: server, documentID: 2))
    // The archives the downgrade removes: not the kept view's member.
    #expect(
      Set(try await database.libraryPinnedFiles(serverID: server).map(\.documentId)) == [1, 3])
  }
}
