import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// `V9` promotes `notes_count` and `current_version_id` out of `document.data`.
/// New rows get them from `DocumentRecord.init(serverId:domain:)`, which the
/// detail-fill tests already cover — what needs its own coverage is the
/// **backfill**, which runs exactly once against rows written before the column
/// existed, and is the only place the JSON path is still walked.
@Suite("V9 document column promotion")
struct DocumentColumnPromotionTests {
  private static let upToV8 = "v8_add_sync_over_cellular"

  private func queueAtV8(server: UUID) throws -> DatabaseQueue {
    var config = Configuration()
    config.prepareDatabase { db in try db.execute(sql: "PRAGMA foreign_keys = ON;") }
    let queue = try DatabaseQueue(configuration: config)
    var migrator = Migrations.migrator(legacyConnectionsUserDefaults: nil)
    migrator.eraseDatabaseOnSchemaChange = false
    try migrator.migrate(queue, upTo: Self.upToV8)
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO server (id, url, user, extra_headers, needs_auth, offline_browsing_mode)
          VALUES (?, ?, ?, '[]', 0, 'recentlyBrowsed')
          """,
        arguments: [
          server, "https://example.com/api/",
          #"{"id":1,"isSuperUser":true,"username":"alice","groups":[]}"#,
        ])
    }
    return queue
  }

  private func insertPreV9(
    _ queue: DatabaseQueue, server: UUID, id: Int, notesCount: Int, versionIDs: [Int]
  ) throws {
    let versions =
      versionIDs
      .map { #"{"added":0,"id":\#($0),"isRoot":false}"# }
      .joined(separator: ",")
    let data = #"{"notesCount":\#(notesCount),"tags":[],"versions":[\#(versions)]}"#
    try queue.write { db in
      try db.execute(
        sql: "INSERT INTO document (server_id, id, title, data) VALUES (?, ?, ?, ?)",
        arguments: [server, id, "doc-\(id)", data])
    }
  }

  private func finishMigrating(_ queue: DatabaseQueue) throws {
    var migrator = Migrations.migrator(legacyConnectionsUserDefaults: nil)
    migrator.eraseDatabaseOnSchemaChange = false
    try migrator.migrate(queue)
  }

  private func columns(_ queue: DatabaseQueue, id: Int) throws -> (notes: Int, version: Int) {
    try queue.read { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT notes_count, current_version_id FROM document WHERE id = ?",
        arguments: [id])!
      return (row["notes_count"], row["current_version_id"])
    }
  }

  @Test("backfills the notes count from the existing blob")
  func backfillsNotesCount() throws {
    let server = UUID()
    let queue = try queueAtV8(server: server)
    try insertPreV9(queue, server: server, id: 1, notesCount: 0, versionIDs: [])
    try insertPreV9(queue, server: server, id: 2, notesCount: 3, versionIDs: [])

    try finishMigrating(queue)

    #expect(try columns(queue, id: 1).notes == 0)
    #expect(try columns(queue, id: 2).notes == 3)
  }

  @Test("backfills current_version_id as the highest version, or the document id")
  func backfillsCurrentVersion() throws {
    let server = UUID()
    let queue = try queueAtV8(server: server)
    // No versions — the overwhelmingly common case, since multi-version support
    // exists only on recent backends. Falls back to the document id.
    try insertPreV9(queue, server: server, id: 10, notesCount: 0, versionIDs: [])
    // Highest id wins, and it is *not* the last one listed.
    try insertPreV9(queue, server: server, id: 20, notesCount: 0, versionIDs: [42, 16])

    try finishMigrating(queue)

    #expect(try columns(queue, id: 10).version == 10)
    #expect(try columns(queue, id: 20).version == 42)
  }

  @Test("the promoted columns match what a freshly written record stores")
  func backfillMatchesRecordWrite() throws {
    // The backfill reproduces `Document.currentVersionID` in SQL, so the two
    // paths have to agree — otherwise an upgraded install and a fresh one
    // disagree about which documents still need a metadata fetch.
    let server = UUID()
    let queue = try queueAtV8(server: server)
    try insertPreV9(queue, server: server, id: 30, notesCount: 2, versionIDs: [7, 99, 12])
    try finishMigrating(queue)
    let backfilled = try columns(queue, id: 30)

    let database = try Database.seeded(serverID: server)
    let document = Document(
      id: 30, title: "d", created: Date(timeIntervalSince1970: 0), tags: [],
      versions: [7, 99, 12].map {
        DocumentVersion(
          id: $0, added: Date(timeIntervalSince1970: 0), label: nil, checksum: nil, isRoot: false)
      })
    try database.upsertDocuments([document], serverID: server)
    let written = try database.writer.read { db in
      try Row.fetchOne(
        db, sql: "SELECT notes_count, current_version_id FROM document WHERE id = 30")!
    }

    #expect(backfilled.version == written["current_version_id"])
    #expect(backfilled.version == 99)
  }
}
