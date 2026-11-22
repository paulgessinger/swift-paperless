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

  // MARK: - resetAfterDowngrade

  @Test("resetAfterDowngrade keeps every list, document row and its detail")
  func resetKeepsListsAndDocuments() async throws {
    let server = UUID()
    let database = try database(server)
    let list = QueryKey(sentinel: "default")
    let view = QueryKey(sentinel: "saved-view")

    try await database.upsertDocuments([doc(1, "A"), doc(2, "B"), doc(3, "C")], serverID: server)
    try await database.replaceQueryOrder(
      queryKey: list, serverID: server, orderedIDs: [1, 2], basis: .initial)
    try await database.replaceQueryOrder(
      queryKey: view, serverID: server, orderedIDs: [3], basis: .initial)
    try await database.setNotes([note(1)], serverID: server, documentID: 3)
    try await database.setFileMetadata(
      metadata("sum"), serverID: server, versionID: 3, documentModified: nil)

    try await database.resetAfterDowngrade(serverID: server)

    #expect(try await database.documentCount(serverID: server) == 3)
    #expect(
      try await database.queryDocuments(queryKey: list, serverID: server, limit: 10).map(\.id)
        == [1, 2])
    #expect(
      try await database.queryDocuments(queryKey: view, serverID: server, limit: 10).map(\.id)
        == [3])
    #expect(try await database.notes(serverID: server, documentID: 3)?.count == 1)
    #expect(try await database.fileMetadata(serverID: server, versionID: 3) != nil)
  }

  @Test("resetAfterDowngrade drops the server's recorded list failures")
  func resetDropsSyncErrors() async throws {
    let server = UUID()
    let other = UUID()
    let database = try database(server)
    try database.upsertConnection(
      ConnectionRecord(
        id: other, url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "bob")))
    for id in [server, other] {
      try await database.recordQuerySyncError(
        serverID: id, queryKey: "saved-view", savedViewName: "Saved", message: "boom")
    }

    try await database.resetAfterDowngrade(serverID: server)

    #expect(try await firstErrors(database, server).isEmpty)
    #expect(try await firstErrors(database, other).count == 1)
  }

  private func firstErrors(_ database: Persistence.Database, _ server: UUID) async throws
    -> [QuerySyncError]
  {
    for try await errors in database.observeQuerySyncErrors(serverID: server) {
      return errors
    }
    return []
  }

  // MARK: - Order completeness

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

  // MARK: - Sync state

  @Test("resetAfterDowngrade clears the library-coverage marker")
  func resetClearsCoverageMarker() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.setLibraryCoverageAt(date(5000), serverID: server)

    try await database.resetAfterDowngrade(serverID: server)

    // A later re-upgrade has to fill the saved views again instead of
    // reading a fresh stamp.
    #expect(try await database.libraryCoverageAt(serverID: server) == nil)
  }

  @Test("resetAfterDowngrade leaves the delta watermark alone")
  func resetKeepsDeltaWatermark() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.setDeltaWatermark(date(7000), serverID: server)
    try await database.setLibraryCoverageAt(date(5000), serverID: server)

    try await database.resetAfterDowngrade(serverID: server)

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

    try await database.resetAfterDowngrade(serverID: server)

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

    try await database.resetAfterDowngrade(serverID: server)

    #expect(try await database.documentCount(serverID: server) == 3)
    #expect(try await database.isKept(serverID: server, documentID: 2))
    // The archives the downgrade removes: not the kept view's member.
    #expect(
      Set(try await database.libraryPinnedFiles(serverID: server).map(\.documentId)) == [1, 3])
  }
}
