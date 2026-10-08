import Foundation
import GRDB
import Testing

@testable import Persistence

@Suite("Database schema")
struct DatabaseSchemaTests {
  @Test("the server table has the expected columns after every migration")
  func serverTableColumns() throws {
    let database = try Database.inMemory()
    try database.writer.read { db in
      let columns = try db.columns(in: "server")
      let names = Set(columns.map(\.name))
      #expect(
        names == [
          "id", "url", "friendly_name", "identity", "user", "extra_headers", "needs_auth",
          "offline_browsing_mode", "sync_over_cellular",
        ])

      // Added by V8 on an existing table, so it needs a default for every row
      // that predates it.
      let cellular = try #require(columns.first(where: { $0.name == "sync_over_cellular" }))
      #expect(cellular.isNotNull)
      #expect(cellular.defaultValueSQL == "0")

      let needsAuth = try #require(columns.first(where: { $0.name == "needs_auth" }))
      #expect(needsAuth.isNotNull)
      // SQLite STRICT enforces declared types; GRDB reports them as upper-cased.
      #expect(needsAuth.type.uppercased() == "INTEGER")

      let id = try #require(columns.first(where: { $0.name == "id" }))
      #expect(id.primaryKeyIndex == 1)
      #expect(id.type.uppercased() == "BLOB")
    }
  }

  @Test("v6 drops the document projection columns and the query_order document FK")
  func v6DropsProjection() throws {
    let database = try Database.inMemory()
    try database.writer.read { db in
      // V4 created projection_level / detail_fetched_at; V6 dropped them.
      let docColumns = Set(try db.columns(in: "document").map(\.name))
      #expect(!docColumns.contains("projection_level"))
      #expect(!docColumns.contains("detail_fetched_at"))
      // `notes_count` / `current_version_id` are V9's promotions out of `data`,
      // `modified` is V12's.
      #expect(
        docColumns == [
          "server_id", "id", "title", "asn", "data", "notes_count", "current_version_id",
          "modified",
        ])

      // query_order no longer FK-references `document` (so it can hold skeletons);
      // its only remaining foreign key is to `server`.
      let fkTargets = Set(try db.foreignKeys(on: "query_order").map(\.destinationTable))
      #expect(fkTargets == ["server"])
    }
  }

  @Test("v7 creates the query_sync_error table with expected columns")
  func v7CreatesQuerySyncError() throws {
    let database = try Database.inMemory()
    try database.writer.read { db in
      #expect(try db.tableExists("query_sync_error"))
      let columns = Set(try db.columns(in: "query_sync_error").map(\.name))
      #expect(columns == ["server_id", "query_key", "saved_view_name", "message", "failed_at"])

      // It cascades from `server` so removing a connection tears down its errors.
      let fkTargets = Set(try db.foreignKeys(on: "query_sync_error").map(\.destinationTable))
      #expect(fkTargets == ["server"])
    }
  }

  @Test("v10 adds a nullable viewed_at to query_meta")
  func v10AddsQueryViewedAt() throws {
    let database = try Database.inMemory()
    try database.writer.read { db in
      let columns = try db.columns(in: "query_meta")

      // Added to an existing table with no backfill, so rows that predate it
      // must be allowed to carry nothing.
      let viewedAt = try #require(columns.first(where: { $0.name == "viewed_at" }))
      #expect(!viewedAt.isNotNull)
      #expect(viewedAt.type.uppercased() == "TEXT")
    }
  }

  @Test("v11 replaces order_stale with two counters and adds placed_modified")
  func v11TracksQueryOrderStaleness() throws {
    let database = try Database.inMemory()
    try database.writer.read { db in
      let meta = try db.columns(in: "query_meta")
      #expect(
        Set(meta.map(\.name)) == [
          "server_id", "query_key", "total_count", "filled_at", "viewed_at",
          "order_generation", "order_basis",
        ])
      for name in ["order_generation", "order_basis"] {
        let column = try #require(meta.first(where: { $0.name == name }))
        #expect(column.isNotNull)
        #expect(column.defaultValueSQL == "0")
      }

      let placed = try #require(
        try db.columns(in: "query_order").first(where: { $0.name == "placed_modified" }))
      #expect(!placed.isNotNull)
      #expect(placed.type.uppercased() == "REAL")
    }
  }

  @Test("v11 keeps stale orders stale and places existing rows under their cached date")
  func v11CarriesStaleFlag() throws {
    let server = UUID()
    let queue = try DatabaseQueue()
    var migrator = Migrations.migrator(legacyConnectionsUserDefaults: nil)
    try migrator.migrate(queue, upTo: "v10_add_query_viewed_at")
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO server (id, url, user, extra_headers, needs_auth, offline_browsing_mode)
          VALUES (?, 'https://example.com/api/', '{"id":1,"isSuperUser":true,"username":"a","groups":[]}', '[]', 0, 'recentlyBrowsed')
          """, arguments: [server])
      try db.execute(
        sql: """
          INSERT INTO query_meta (server_id, query_key, order_stale)
          VALUES (?, 'stale', 1), (?, 'clean', 0)
          """, arguments: [server, server])
      // Document 1 is cached, document 2 is a skeleton.
      try db.execute(
        sql: """
          INSERT INTO document (server_id, id, title, data)
          VALUES (?, 1, 'A', '{"created":0,"modified":1234.5,"tags":[],"versions":[]}')
          """, arguments: [server])
      try db.execute(
        sql: """
          INSERT INTO query_order (server_id, query_key, position, remote_id)
          VALUES (?, 'clean', 0, 1), (?, 'clean', 1, 2)
          """, arguments: [server, server])
    }
    migrator.eraseDatabaseOnSchemaChange = false
    try migrator.migrate(queue)

    try queue.read { db in
      let stale = try Database.fetchQueryMeta(
        db, queryKey: QueryKey(sentinel: "stale"), serverID: server)
      let clean = try Database.fetchQueryMeta(
        db, queryKey: QueryKey(sentinel: "clean"), serverID: server)
      #expect(stale?.orderStale == true)
      #expect(clean?.orderStale == false)

      // Existing rows are placed under their cached document's date.
      let placed = try Double?.fetchAll(
        db, sql: "SELECT placed_modified FROM query_order ORDER BY position")
      #expect(placed == [1234.5, nil])
    }
  }

  @Test("v12 promotes document.modified to a column, backfilled from the blob")
  func v12PromotesDocumentModified() throws {
    let server = UUID()
    let queue = try DatabaseQueue()
    var migrator = Migrations.migrator(legacyConnectionsUserDefaults: nil)
    try migrator.migrate(queue, upTo: "v11_track_query_order_staleness")
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO server (id, url, user, extra_headers, needs_auth, offline_browsing_mode)
          VALUES (?, 'https://example.com/api/', '{"id":1,"isSuperUser":true,"username":"a","groups":[]}', '[]', 0, 'recentlyBrowsed')
          """, arguments: [server])
      try db.execute(
        sql: """
          INSERT INTO document (server_id, id, title, data) VALUES
            (?, 1, 'A', '{"created":0,"modified":1234.5,"tags":[],"versions":[]}'),
            (?, 2, 'B', '{"created":0,"tags":[],"versions":[]}')
          """, arguments: [server, server])
    }
    migrator.eraseDatabaseOnSchemaChange = false
    try migrator.migrate(queue)

    try queue.read { db in
      let column = try #require(
        try db.columns(in: "document").first(where: { $0.name == "modified" }))
      #expect(!column.isNotNull)
      #expect(column.type.uppercased() == "REAL")

      let modified = try Double?.fetchAll(db, sql: "SELECT modified FROM document ORDER BY id")
      #expect(modified == [1234.5, nil])
    }
  }

  @Test("v13 dates existing file metadata by its current document's modified")
  func v13BackfillsFileMetadataDocumentModified() throws {
    let server = UUID()
    let queue = try DatabaseQueue()
    var migrator = Migrations.migrator(legacyConnectionsUserDefaults: nil)
    try migrator.migrate(queue, upTo: "v12_promote_document_modified")
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO server (id, url, user, extra_headers, needs_auth, offline_browsing_mode)
          VALUES (?, 'https://example.com/api/', '{"id":1,"isSuperUser":true,"username":"a","groups":[]}', '[]', 0, 'recentlyBrowsed')
          """, arguments: [server])
      // Document 1's current version is 9; version 1 is an older one.
      try db.execute(
        sql: """
          INSERT INTO document (server_id, id, title, data, current_version_id, modified)
          VALUES (?, 1, 'A', '{}', 9, 1234.5)
          """, arguments: [server])
      try db.execute(
        sql: """
          INSERT INTO file_metadata (server_id, version_id, data)
          VALUES (?, 1, '{}'), (?, 9, '{}')
          """, arguments: [server, server])
    }
    migrator.eraseDatabaseOnSchemaChange = false
    try migrator.migrate(queue)

    try queue.read { db in
      let column = try #require(
        try db.columns(in: "file_metadata").first(where: { $0.name == "document_modified" }))
      #expect(!column.isNotNull)
      #expect(column.type.uppercased() == "REAL")

      let dates = try Double?.fetchAll(
        db, sql: "SELECT document_modified FROM file_metadata ORDER BY version_id")
      #expect(dates == [nil, 1234.5])
    }
  }

  @Test("v14 adds the freshness stamps as empty, keeping the existing sync state")
  func v14AddsSyncFreshnessColumns() throws {
    let server = UUID()
    let queue = try DatabaseQueue()
    var migrator = Migrations.migrator(legacyConnectionsUserDefaults: nil)
    try migrator.migrate(queue, upTo: "v13_track_file_metadata_document_modified")
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO server (id, url, user, extra_headers, needs_auth, offline_browsing_mode)
          VALUES (?, 'https://example.com/api/', '{"id":1,"isSuperUser":true,"username":"a","groups":[]}', '[]', 0, 'recentlyBrowsed')
          """, arguments: [server])
      try db.execute(
        sql: """
          INSERT INTO server_sync_state (server_id, delta_watermark, library_coverage_at)
          VALUES (?, 100.5, 200.5)
          """, arguments: [server])
    }
    migrator.eraseDatabaseOnSchemaChange = false
    try migrator.migrate(queue)

    try queue.read { db in
      let columns = try db.columns(in: "server_sync_state")
      for name in ["last_reconcile_at", "last_successful_sync_at"] {
        let column = try #require(columns.first(where: { $0.name == name }))
        #expect(!column.isNotNull)
        #expect(column.type.uppercased() == "REAL")
      }

      let row = try #require(
        try Row.fetchOne(
          db,
          sql: """
            SELECT delta_watermark, library_coverage_at, last_reconcile_at, last_successful_sync_at
            FROM server_sync_state
            """))
      #expect(row["delta_watermark"] as Double? == 100.5)
      #expect(row["library_coverage_at"] as Double? == 200.5)
      #expect(row["last_reconcile_at"] as Double? == nil)
      #expect(row["last_successful_sync_at"] as Double? == nil)
    }
  }

  @Test("migrator tracks applied identifiers internally")
  func migratorTracksAppliedIdentifiers() throws {
    let database = try Database.inMemory()
    // GRDB maintains its own grdb_migrations table; both registered
    // migrations should appear after init.
    let applied = try database.writer.read { db in
      try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
    }
    #expect(applied.contains("v1_create_server"))
    #expect(applied.contains(V2_ImportLegacyConnections.identifier))
  }

  @Test("PRAGMA foreign_keys is on")
  func foreignKeysOn() throws {
    let database = try Database.inMemory()
    try database.writer.read { db in
      let enabled = try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") ?? false
      #expect(enabled)
    }
  }

  @Test("STRICT mode rejects wrong-typed values")
  func strictModeRejectsWrongTypes() throws {
    let database = try Database.inMemory()
    // `needs_auth` is INTEGER NOT NULL; inserting a TEXT should fail with
    // SQLITE_CONSTRAINT_DATATYPE under STRICT.
    #expect(throws: (any Error).self) {
      try database.writer.write { db in
        try db.execute(
          sql: """
            INSERT INTO server (id, url, user, needs_auth)
            VALUES (?, ?, ?, ?)
            """,
          arguments: [Data([0x00]), "https://example.com", "{}", "not-an-int"])
      }
    }
  }

  @Test("re-running migrations is idempotent")
  func reRunningMigrationsIsIdempotent() throws {
    let database = try Database.inMemory()
    // Initial migration already ran during init(). Running again must be a
    // no-op (the migrator tracks applied identifiers).
    try Migrations.migrator(legacyConnectionsUserDefaults: nil).migrate(database.writer)
    let serverExists = try database.writer.read { db in
      try db.tableExists("server")
    }
    #expect(serverExists)
  }

  @Test("v4 indexes document.asn for the ASN-scanner lookup")
  func v4IndexesDocumentAsn() throws {
    let database = try Database.inMemory()
    try database.writer.read { db in
      let indexed = try db.indexes(on: "document").contains { index in
        index.columns == ["server_id", "asn"]
      }
      #expect(indexed)
    }
  }
}
