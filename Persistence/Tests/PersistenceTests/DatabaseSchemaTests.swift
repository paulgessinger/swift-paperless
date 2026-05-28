import Foundation
import GRDB
import Testing

@testable import Persistence

@Suite("Database schema")
struct DatabaseSchemaTests {
  @Test("v1 creates the server table with expected columns")
  func v1CreatesServerTable() throws {
    let database = try Database.inMemory()
    try database.writer.read { db in
      let columns = try db.columns(in: "server")
      let names = Set(columns.map(\.name))
      #expect(
        names == [
          "id", "url", "friendly_name", "identity", "user", "extra_headers", "needs_auth",
          "offline_browsing_mode",
        ])

      let needsAuth = try #require(columns.first(where: { $0.name == "needs_auth" }))
      #expect(needsAuth.isNotNull)
      // SQLite STRICT enforces declared types; GRDB reports them as upper-cased.
      #expect(needsAuth.type.uppercased() == "INTEGER")

      let id = try #require(columns.first(where: { $0.name == "id" }))
      #expect(id.primaryKeyIndex == 1)
      #expect(id.type.uppercased() == "BLOB")
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
}
