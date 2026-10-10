import Common
import DataModel
import Foundation
import Testing

@testable import Persistence

/// `Database.statistics()`: the debug menu's look at the database's bookkeeping.
@Suite("DatabaseStatistics", .bug("https://github.com/paulgessinger/swift-paperless/issues/674"))
struct DatabaseStatisticsTests {
  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func doc(_ id: UInt, notes: Int = 0, modified: Date? = nil) -> Document {
    Document(
      id: id, title: "d\(id)", created: date(1000), tags: [], modified: modified,
      owner: .user(1), notes: NotesPayload(count: notes))
  }

  private let metadata = Metadata(
    originalChecksum: "checksum", originalSize: 1234, originalMimeType: "application/pdf",
    mediaFilename: "scan.pdf", hasArchiveVersion: false, originalMetadata: [],
    originalFilename: "scan.pdf", lang: "en")

  private let list = QueryKey(sentinel: "list")
  private let other = QueryKey(sentinel: "other")

  @Test("migrations and table counts cover the whole schema")
  func schemaLevel() async throws {
    let database = try Database.seeded(documents: [doc(1), doc(2)])

    let stats = try await database.statistics()

    #expect(stats.appliedMigrations.count == stats.registeredMigrationCount)
    #expect(stats.appliedMigrations.first == "v1_create_server")
    #expect(!stats.didEraseForSchemaChangeAtLaunch)
    #expect(!stats.sqliteVersion.isEmpty)
    #expect(stats.journalMode == "memory")
    #expect(stats.pageCount > 0)
    #expect(stats.pageSize > 0)
    #expect(stats.diskUsageBytes == 0)
    #expect(stats.evictableFileBytes == 0)

    let rows = Dictionary(uniqueKeysWithValues: stats.tables.map { ($0.name, $0.rows) })
    #expect(rows["server"] == 1)
    #expect(rows["document"] == 2)
    #expect(rows["query_order"] == 0)
    #expect(rows["grdb_migrations"] == stats.registeredMigrationCount)
    // Every cache table appears without being listed by hand.
    for table in [
      "tag", "query_meta", "server_sync_state", "query_sync_error", "file_metadata", "file",
    ] {
      #expect(rows[table] == 0, "\(table)")
    }
    #expect(!rows.keys.contains { $0.hasPrefix("sqlite_") })
    #expect(stats.tables.map(\.name) == stats.tables.map(\.name).sorted())
  }

  @Test("per-server state, backlogs and lists are reported for each server")
  func perServer() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let quiet = UUID()
    try database.upsertConnection(
      ConnectionRecord(
        id: quiet, url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 2, isSuperUser: false, username: "other"), needsAuth: true,
        offlineBrowsingMode: "entireLibrary", syncOverCellular: true))

    // `list`: a fill of two of five documents, viewed, then one of them marked.
    try await database.replaceQueryPage(
      queryKey: list, serverID: server,
      documents: [doc(1, notes: 2, modified: date(5000)), doc(2)],
      totalCount: 5, basis: .initial)
    try await database.markQueryFillComplete(queryKey: list, serverID: server)
    try await database.markQueryViewed(queryKey: list, serverID: server, at: date(2000))
    try await database.markQueriesOrderStale(containing: 1, serverID: server)
    // `other`: one cached document and one skeleton.
    try await database.replaceQueryOrder(
      queryKey: other, serverID: server, orderedIDs: [2, 99], basis: .initial)
    // A document no list references, and a list known only by its error.
    try await database.upsertDocuments([doc(3)], serverID: server)
    try await database.recordQuerySyncError(
      serverID: server, queryKey: "broken", savedViewName: "Inbox", message: "rejected",
      at: date(3000))
    try await database.setDeltaWatermark(date(4000), serverID: server)
    // File metadata: fetched under an older `modified` for 1, current for 2,
    // absent for 3.
    try await database.setFileMetadata(
      metadata, serverID: server, versionID: 1, documentModified: date(4000))
    try await database.setFileMetadata(
      metadata, serverID: server, versionID: 2, documentModified: nil)

    // Cached files: an archive and a thumbnail for 1, an original for 2.
    let archive = ContentStore.Key(serverID: server, versionID: 1, kind: .archive)
    try await database.recordFile(
      archive, documentID: 1, size: 100, modified: date(5000), checksum: nil, storedAt: date(1),
      lastAccessedAt: date(1))
    try await database.recordFile(
      ContentStore.Key(serverID: server, versionID: 1, kind: .thumbnail), documentID: 1, size: 5,
      modified: nil, checksum: nil, storedAt: date(1), lastAccessedAt: nil)
    try await database.recordFile(
      ContentStore.Key(serverID: server, versionID: 2, kind: .original), documentID: 2, size: 40,
      modified: nil, checksum: nil, storedAt: date(1), lastAccessedAt: date(1))

    let stats = try await database.statistics()

    #expect(stats.evictableFileBytes == 140)
    #expect(Set(stats.servers.map(\.id)) == [server, quiet])
    let main = try #require(stats.servers.first { $0.id == server })
    #expect(main.offlineBrowsingMode == "recentlyBrowsed")
    #expect(!main.syncOverCellular)
    #expect(!main.needsAuth)
    #expect(main.deltaWatermark == date(4000))
    #expect(main.libraryCoverageAt == nil)
    #expect(main.rowsByTable["document"] == 3)
    #expect(main.rowsByTable["query_order"] == 4)
    #expect(main.rowsByTable["query_meta"] == 2)
    #expect(main.rowsByTable["query_sync_error"] == 1)
    #expect(main.rowsByTable["server_sync_state"] == 1)
    #expect(main.rowsByTable["tag"] == nil)
    #expect(main.skeletonRows == 1)
    #expect(main.unreferencedDocuments == 1)
    #expect(main.documentsAwaitingNotes == 1)
    #expect(main.documentsAwaitingFileMetadata == 2)
    #expect(main.rowsByTable["file"] == 3)
    #expect(
      main.files == [
        .init(kind: "archive", count: 1, bytes: 100), .init(kind: "original", count: 1, bytes: 40),
        .init(kind: "thumbnail", count: 1, bytes: 5),
      ])

    #expect(main.queries.map(\.id) == ["broken", "list", "other"])
    let filled = try #require(main.queries.first { $0.key == list })
    #expect(filled.totalCount == 5)
    #expect(filled.orderRows == 2)
    #expect(filled.lastPosition == 1)
    #expect(filled.skeletonRows == 0)
    #expect(filled.unknownPlacementRows == 1)
    #expect(filled.filledAt != nil)
    #expect(filled.viewedAt == date(2000))
    #expect(filled.orderGeneration == 1)
    #expect(filled.orderBasis == 0)
    #expect(filled.orderStale)
    #expect(filled.syncError == nil)

    let skeletal = try #require(main.queries.first { $0.key == other })
    #expect(skeletal.orderRows == 2)
    #expect(skeletal.skeletonRows == 1)
    #expect(skeletal.totalCount == 2)
    #expect(skeletal.filledAt == nil)
    #expect(!skeletal.orderStale)

    let broken = try #require(main.queries.first { $0.id == "broken" })
    #expect(broken.orderRows == 0)
    #expect(broken.totalCount == nil)
    #expect(
      broken.syncError
        == .init(savedViewName: "Inbox", message: "rejected", failedAt: date(3000)))

    let idle = try #require(stats.servers.first { $0.id == quiet })
    #expect(idle.offlineBrowsingMode == "entireLibrary")
    #expect(idle.syncOverCellular)
    #expect(idle.needsAuth)
    #expect(idle.deltaWatermark == nil)
    #expect(idle.rowsByTable.isEmpty)
    #expect(idle.files.isEmpty)
    #expect(idle.queries.isEmpty)
    #expect(idle.skeletonRows == 0)
  }

  @Test("an on-disk database reports WAL mode and its file size")
  func onDisk() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("DatabaseStatisticsTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = try Persistence.Database(path: directory.appendingPathComponent("test.sqlite"))

    let stats = try await database.statistics()

    #expect(stats.journalMode == "wal")
    #expect(stats.diskUsageBytes == database.diskUsage().bytes)
    #expect(stats.diskUsageBytes > 0)
    #expect(stats.servers.isEmpty)
  }
}
