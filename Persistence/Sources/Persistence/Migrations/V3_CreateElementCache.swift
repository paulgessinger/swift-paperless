import GRDB

/// Element-metadata cache tables (Stage 7).
///
/// Each multi-row element collection is keyed `(server_id, id)` and carries a
/// `name` column (display/sort) plus a `data` JSON column for the long tail.
/// `ui_settings` and `server_configuration` are per-server singletons keyed by
/// `server_id` alone. Every table FK-references `server(id)` with
/// `ON DELETE CASCADE`, so removing a connection tears down its whole cache —
/// the Stage 10 "connection lifecycle = cache lifecycle" rule, for free.
enum V3_CreateElementCache {
  static let multiRowTables = [
    "tag", "correspondent", "document_type", "storage_path",
    "saved_view", "user", "user_group", "custom_field",
  ]
  static let singletonTables = ["ui_settings", "server_configuration"]

  static func run(_ db: GRDB.Database) throws {
    for table in multiRowTables {
      try db.create(table: table, options: [.strict]) { t in
        t.column("server_id", .blob)
          .notNull()
          .references("server", onDelete: .cascade)
        t.column("id", .integer).notNull()
        t.column("name", .text).notNull()
        t.column("data", .text).notNull()
        t.primaryKey(["server_id", "id"])
      }
    }

    for table in singletonTables {
      try db.create(table: table, options: [.strict]) { t in
        t.primaryKey("server_id", .blob)
          .references("server", onDelete: .cascade)
        t.column("data", .text).notNull()
      }
    }
  }
}
