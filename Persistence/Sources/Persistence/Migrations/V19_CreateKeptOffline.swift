import GRDB

/// The documents the user keeps on the device: the membership of the local
/// *Kept offline* view, one row per `(server, document)`.
///
/// Configuration, not cache: like `server.offline_browsing_mode` it survives
/// `clearCache`, so it is not in any `tables` list. No FK to `document`; the
/// document row is cache and may be missing until the next sync fetches it,
/// which the list shows as a skeleton. Cascade-deleted with its `server`.
enum V19_CreateKeptOffline {
  static func run(_ db: GRDB.Database) throws {
    try db.create(table: "kept_offline", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("document_id", .integer).notNull()
      // `timeIntervalSinceReferenceDate` (REAL); the list orders by it.
      t.column("kept_at", .real).notNull()
      t.primaryKey(["server_id", "document_id"])
    }
  }
}
