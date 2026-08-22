import Foundation
import GRDB
import Testing

@testable import Persistence

/// `V6` rebuilds `query_order` — create-new / copy / drop / rename — because
/// SQLite can't drop a foreign key in place. A rebuilt table inherits **nothing**
/// implicitly: not the constraints, not the indices, and not the rows unless the
/// copy names every column.
///
/// The rest of the schema suite runs against `Database.inMemory()`, which
/// migrates an *empty* file in one pass — so the copy step there always moves
/// zero rows and could be deleted without a single test noticing. These tests
/// migrate to `V5`, put rows in, and only then finish the migration, which is
/// what an actual upgrade does.
@Suite("V6 query_order rebuild")
struct QueryOrderRebuildTests {
  private static let upToV5 = "v5_create_document_detail_cache"

  /// A queue migrated as far as `V5`, with one server and three cached
  /// documents, ready for `query_order` rows.
  private func queueAtV5(server: UUID) throws -> DatabaseQueue {
    var config = Configuration()
    config.prepareDatabase { db in try db.execute(sql: "PRAGMA foreign_keys = ON;") }
    let queue = try DatabaseQueue(configuration: config)
    var migrator = Migrations.migrator(legacyConnectionsUserDefaults: nil)
    // The DEBUG convenience that wipes on a schema change would defeat the point
    // of migrating in two steps.
    migrator.eraseDatabaseOnSchemaChange = false
    try migrator.migrate(queue, upTo: Self.upToV5)

    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO server
            (id, url, user, extra_headers, needs_auth, offline_browsing_mode)
          VALUES (?, ?, ?, '[]', 0, 'recentlyBrowsed')
          """,
        arguments: [
          server, "https://example.com/api/",
          #"{"id":1,"isSuperUser":true,"username":"alice","groups":[]}"#,
        ])
      for id in [10, 20, 30] {
        // V4's shape, including `projection_level` — the column V6 drops. The
        // insert has to match the schema as of V5, not today's record type.
        try db.execute(
          sql: """
            INSERT INTO document (server_id, id, title, projection_level, data)
            VALUES (?, ?, ?, 1, ?)
            """,
          arguments: [server, id, "doc-\(id)", #"{"id":\#(id)}"#])
      }
    }
    return queue
  }

  private func finishMigrating(_ queue: DatabaseQueue) throws {
    var migrator = Migrations.migrator(legacyConnectionsUserDefaults: nil)
    migrator.eraseDatabaseOnSchemaChange = false
    try migrator.migrate(queue)
  }

  @Test("the rebuild carries every row across, with its columns in the right places")
  func rebuildPreservesRows() throws {
    let server = UUID()
    let queue = try queueAtV5(server: server)

    try queue.write { db in
      // Deliberately not in position order, and with a gap, so a copy that
      // silently reordered or renumbered would show up.
      for (position, remoteID) in [(2, 30), (0, 10), (5, 20)] {
        try db.execute(
          sql: """
            INSERT INTO query_order (server_id, query_key, position, remote_id)
            VALUES (?, 'k', ?, ?)
            """,
          arguments: [server, position, remoteID])
      }
    }

    try finishMigrating(queue)

    let rows = try queue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT position, remote_id FROM query_order
          WHERE server_id = ? AND query_key = 'k' ORDER BY position
          """,
        arguments: [server])
    }
    let pairs = rows.map { ($0["position"] as Int, $0["remote_id"] as Int) }
    #expect(pairs.map(\.0) == [0, 2, 5])
    #expect(pairs.map(\.1) == [10, 30, 20])
  }

  @Test("the rebuild recreates the reverse-lookup index")
  func rebuildRecreatesIndex() throws {
    let server = UUID()
    let queue = try queueAtV5(server: server)
    try finishMigrating(queue)

    // Dropping and renaming the table takes its indices with it; `V6` has to put
    // this one back or every `query_order` lookup by document id table-scans.
    let indexed = try queue.read { db in
      try db.indexes(on: "query_order").contains { $0.columns == ["server_id", "remote_id"] }
    }
    #expect(indexed)
  }

  @Test("the rebuilt table still refuses a duplicate remote_id for one query")
  func rebuildKeepsUniqueKey() throws {
    let server = UUID()
    let queue = try queueAtV5(server: server)
    try finishMigrating(queue)

    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO query_order (server_id, query_key, position, remote_id)
          VALUES (?, 'k', 0, 10), (?, 'k', 1, 10)
          """,
        arguments: [server, server])
    }

    // `onConflict: .ignore` on the unique key: the repeat is skipped, not stored
    // at a second position and not an error. A rebuilt table inherits no
    // constraints, so without V6 restating this the row lands twice and the
    // windowed replay emits the same document id twice.
    let count = try queue.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM query_order WHERE server_id = ?", arguments: [server])
    }
    #expect(count == 1)
  }

  @Test("the rebuilt table still replaces on a position collision")
  func rebuildKeepsPositionConflictClause() throws {
    let server = UUID()
    let queue = try queueAtV5(server: server)
    try finishMigrating(queue)

    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO query_order (server_id, query_key, position, remote_id)
          VALUES (?, 'k', 0, 10), (?, 'k', 0, 20)
          """,
        arguments: [server, server])
    }

    // `onConflict: .replace` on the primary key: re-writing a position
    // overwrites rather than aborting the whole page write.
    let remoteID = try queue.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT remote_id FROM query_order WHERE server_id = ? AND position = 0",
        arguments: [server])
    }
    #expect(remoteID == 20)
  }

  @Test("the rebuilt table drops the document foreign key, so skeletons are legal")
  func rebuildDropsDocumentForeignKey() throws {
    let server = UUID()
    let queue = try queueAtV5(server: server)
    try finishMigrating(queue)

    // The whole point of the rebuild: membership can name a document that isn't
    // cached yet, which is what renders as a skeleton row.
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO query_order (server_id, query_key, position, remote_id)
          VALUES (?, 'k', 0, 999)
          """,
        arguments: [server])
    }
    let count = try queue.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM query_order WHERE remote_id = 999")
    }
    #expect(count == 1)
  }
}
