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

  // MARK: - Orphan reclaim

  @Test("deletes a document referenced by no query_order row")
  func deletesUnreferencedDocument() throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")

    try database.upsertDocuments([doc(1, "A"), doc(2, "B")], serverID: server)
    // Only doc 1 is tracked by any query.
    try database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [1])

    let removed = try database.pruneUnreferencedDocuments(serverID: server)

    #expect(removed == 1)
    #expect(try database.document(serverID: server, id: 1) != nil)
    #expect(try database.document(serverID: server, id: 2) == nil)
  }

  @Test("preserves a document referenced by at least one query, even if others dropped it")
  func preservesDocumentStillReferencedElsewhere() throws {
    let server = UUID()
    let database = try database(server)
    let keyA = QueryKey(sentinel: "A")
    let keyB = QueryKey(sentinel: "B")

    try database.upsertDocuments([doc(1, "A")], serverID: server)
    try database.replaceQueryOrder(queryKey: keyA, serverID: server, orderedIDs: [1])
    try database.replaceQueryOrder(queryKey: keyB, serverID: server, orderedIDs: [])

    let removed = try database.pruneUnreferencedDocuments(serverID: server)

    #expect(removed == 0)
    #expect(try database.document(serverID: server, id: 1) != nil)
  }

  @Test("is a no-op when every cached document is still referenced")
  func noOpWhenFullyReferenced() throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")

    try database.upsertDocuments([doc(1, "A"), doc(2, "B")], serverID: server)
    try database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [1, 2])

    #expect(try database.pruneUnreferencedDocuments(serverID: server) == 0)
    #expect(try database.document(serverID: server, id: 1) != nil)
    #expect(try database.document(serverID: server, id: 2) != nil)
  }

  @Test("is scoped to one server")
  func scopedToOneServer() throws {
    let serverA = UUID()
    let serverB = UUID()
    let database = try database(serverA)
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "bob")))

    // Neither server's document is referenced by any query.
    try database.upsertDocuments([doc(1, "A")], serverID: serverA)
    try database.upsertDocuments([doc(1, "A")], serverID: serverB)

    let removed = try database.pruneUnreferencedDocuments(serverID: serverA)

    #expect(removed == 1)
    #expect(try database.document(serverID: serverA, id: 1) == nil)
    #expect(try database.document(serverID: serverB, id: 1) != nil)
  }

  // MARK: - Detail-cache cleanup

  @Test("also drops the orphaned document's notes and file-metadata")
  func dropsDetailCacheForOrphan() throws {
    let server = UUID()
    let database = try database(server)

    try database.upsertDocuments([doc(1, "A")], serverID: server)
    try database.setNotes([note(1)], serverID: server, documentID: 1)
    try database.setFileMetadata(metadata("sum"), serverID: server, versionID: 1)
    // Not referenced by any query.

    _ = try database.pruneUnreferencedDocuments(serverID: server)

    #expect(try database.notes(serverID: server, documentID: 1) == nil)
    #expect(try database.fileMetadata(serverID: server, versionID: 1) == nil)
  }

  @Test("cleans up file-metadata for every recorded version, not just the current one")
  func dropsFileMetadataForEveryVersion() throws {
    let server = UUID()
    let database = try database(server)

    try database.upsertDocuments(
      [
        doc(
          1, "A",
          versions: [
            DocumentVersion(id: 1, added: date(1000), isRoot: true),
            DocumentVersion(id: 9, added: date(5000), isRoot: false),
          ])
      ], serverID: server)
    try database.setFileMetadata(metadata("root"), serverID: server, versionID: 1)
    try database.setFileMetadata(metadata("v9"), serverID: server, versionID: 9)
    // Not referenced by any query.

    _ = try database.pruneUnreferencedDocuments(serverID: server)

    #expect(try database.fileMetadata(serverID: server, versionID: 1) == nil)
    #expect(try database.fileMetadata(serverID: server, versionID: 9) == nil)
  }

  // MARK: - dropQueryOrder

  @Test("dropQueryOrder removes every other query's order/meta/sync-error, keeps the given one")
  func dropQueryOrderKeepsOnlyGivenKey() throws {
    let server = UUID()
    let database = try database(server)
    let keep = QueryKey(sentinel: "default")
    let drop = QueryKey(sentinel: "saved-view")

    try database.upsertDocuments([doc(1, "A"), doc(2, "B")], serverID: server)
    try database.replaceQueryOrder(queryKey: keep, serverID: server, orderedIDs: [1, 2])
    try database.replaceQueryOrder(queryKey: drop, serverID: server, orderedIDs: [1, 2])
    try database.recordQuerySyncError(
      serverID: server, queryKey: drop.rawValue, savedViewName: "Saved", message: "boom")

    try database.dropQueryOrder(serverID: server, exceptQueryKey: keep)

    #expect(
      try database.queryDocuments(queryKey: keep, serverID: server, limit: 10).map(\.id) == [
        1, 2,
      ])
    #expect(try database.queryDocuments(queryKey: drop, serverID: server, limit: 10).isEmpty)
    // query_meta gone too: totalCount reads nil, not just localCount == 0.
    #expect(try database.queryStatus(queryKey: drop, serverID: server).totalCount == nil)
    #expect(try database.queryStatus(queryKey: keep, serverID: server).totalCount == 2)
  }

  // MARK: - truncateQueryOrder

  @Test("truncateQueryOrder keeps only the first N positions")
  func truncateKeepsPrefix() throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "default")

    try database.upsertDocuments((1...5).map { doc($0, "d\($0)") }, serverID: server)
    try database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [1, 2, 3, 4, 5])

    try database.truncateQueryOrder(serverID: server, queryKey: key, keepingFirst: 3)

    #expect(
      try database.queryDocuments(queryKey: key, serverID: server, limit: 10).map(\.id) == [
        1, 2, 3,
      ])
    // The server's true total is untouched by the local cap.
    #expect(try database.queryStatus(queryKey: key, serverID: server).totalCount == 5)
  }

  @Test("truncateQueryOrder counts rows, not position values, when positions are gappy")
  func truncateCountsRowsNotPositions() throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "default")

    try database.upsertDocuments((1...5).map { doc($0, "d\($0)") }, serverID: server)
    try database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [1, 2, 3, 4, 5])
    // Punch a hole the way a page-boundary repeat or a remote delete does: the
    // surviving rows now sit at positions 0, 2, 3, 4 rather than 0...3.
    try database.deleteDocuments(serverID: server, removedIDs: [2])

    try database.truncateQueryOrder(serverID: server, queryKey: key, keepingFirst: 3)

    // Three rows kept. A `position < 3` test would have kept only two (0 and 2).
    #expect(
      try database.queryDocuments(queryKey: key, serverID: server, limit: 10).map(\.id) == [
        1, 3, 4,
      ])
  }

  // MARK: - reclaimAfterDowngrade

  @Test("reclaimAfterDowngrade drops, truncates and prunes in one call")
  func reclaimDoesTheWholeSequence() throws {
    let server = UUID()
    let database = try database(server)
    let keep = QueryKey(sentinel: "default")
    let drop = QueryKey(sentinel: "saved-view")

    try database.upsertDocuments((1...6).map { doc($0, "d\($0)") }, serverID: server)
    try database.replaceQueryOrder(
      queryKey: keep, serverID: server, orderedIDs: [1, 2, 3, 4])
    // 5 and 6 are only reachable through the saved view.
    try database.replaceQueryOrder(queryKey: drop, serverID: server, orderedIDs: [5, 6])

    let removed = try database.reclaimAfterDowngrade(
      serverID: server, defaultQueryKey: keep, keepingFirst: 2)

    // 5 and 6 lost their only reference; 3 and 4 fell off the truncated prefix.
    #expect(removed == 4)
    #expect(
      try database.queryDocuments(queryKey: keep, serverID: server, limit: 10).map(\.id) == [1, 2])
    #expect(try database.queryDocuments(queryKey: drop, serverID: server, limit: 10).isEmpty)
    #expect(try database.document(serverID: server, id: 5) == nil)
  }

  @Test("reclaimAfterDowngrade clears the library-coverage marker")
  func reclaimClearsCoverageMarker() throws {
    let server = UUID()
    let database = try database(server)
    let keep = QueryKey(sentinel: "default")

    try database.upsertDocuments([doc(1, "A")], serverID: server)
    try database.replaceQueryOrder(queryKey: keep, serverID: server, orderedIDs: [1])
    try database.setLibraryCoverageAt(date(5000), serverID: server)

    try database.reclaimAfterDowngrade(
      serverID: server, defaultQueryKey: keep, keepingFirst: 200)

    // The cache no longer matches what the marker claimed, so a later
    // re-upgrade has to re-fill instead of reading a fresh stamp.
    #expect(try database.libraryCoverageAt(serverID: server) == nil)
  }

  @Test("reclaimAfterDowngrade leaves the delta watermark alone")
  func reclaimKeepsDeltaWatermark() throws {
    let server = UUID()
    let database = try database(server)
    let keep = QueryKey(sentinel: "default")

    try database.upsertDocuments([doc(1, "A")], serverID: server)
    try database.replaceQueryOrder(queryKey: keep, serverID: server, orderedIDs: [1])
    try database.setDeltaWatermark(date(7000), serverID: server)
    try database.setLibraryCoverageAt(date(5000), serverID: server)

    try database.reclaimAfterDowngrade(
      serverID: server, defaultQueryKey: keep, keepingFirst: 200)

    // Documents that survive the reclaim still want their changes applied, so
    // the delta must not re-baseline over them.
    #expect(try database.deltaWatermark(serverID: server) == date(7000))
  }

  // MARK: - End-to-end downgrade sequence

  @Test("drop-non-default + truncate-default + prune actually shrinks the cache")
  func downgradeSequenceShrinksCache() throws {
    // Reproduces the reported gap: after an entire-library-style fill, both
    // the default list and a saved view reference every document, so
    // pruneUnreferencedDocuments alone finds nothing to reclaim.
    let server = UUID()
    let database = try database(server)
    let defaultKey = QueryKey(sentinel: "default")
    let savedViewKey = QueryKey(sentinel: "saved-view")

    let allDocs = (1...10).map { doc($0, "d\($0)") }
    try database.upsertDocuments(allDocs, serverID: server)
    try database.replaceQueryOrder(
      queryKey: defaultKey, serverID: server, orderedIDs: allDocs.map(\.id))
    try database.replaceQueryOrder(
      queryKey: savedViewKey, serverID: server, orderedIDs: allDocs.map(\.id))

    #expect(try database.pruneUnreferencedDocuments(serverID: server) == 0)
    #expect(try database.documentCount(serverID: server) == 10)

    // The actual downgrade sequence (mirrors ConnectionManager.runDowngradeGC).
    try database.dropQueryOrder(serverID: server, exceptQueryKey: defaultKey)
    try database.truncateQueryOrder(serverID: server, queryKey: defaultKey, keepingFirst: 3)
    let removed = try database.pruneUnreferencedDocuments(serverID: server)

    #expect(removed == 7)
    #expect(try database.documentCount(serverID: server) == 3)
    #expect(
      try database.queryDocuments(queryKey: defaultKey, serverID: server, limit: 10).map(\.id)
        == [1, 2, 3])
    #expect(
      try database.queryDocuments(queryKey: savedViewKey, serverID: server, limit: 10).isEmpty)
  }
}
