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
      #expect(docColumns == ["server_id", "id", "title", "asn", "data"])

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
