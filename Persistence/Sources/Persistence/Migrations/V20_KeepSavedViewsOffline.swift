import GRDB

/// Saved views can be kept offline, and a kept view's documents are kept
/// through it.
///
/// `kept_offline` gains `saved_view_id`: 0 for a document kept on its own,
/// otherwise the kept view that keeps it. A document kept both ways has a row
/// for each, so every protection still asks only whether a row exists, and
/// stopping one reason leaves the other. The table is rebuilt for the new
/// primary key; existing rows are kept on their own.
///
/// `kept_offline_view` lists the kept views, keyed by the saved view's id so a
/// view edited on the server stays kept. Configuration, not cache, like
/// `kept_offline`: it survives `clearCache` and cascades with its `server`. No
/// FK to `saved_view`, which is cache.
enum V20_KeepSavedViewsOffline {
  static func run(_ db: GRDB.Database) throws {
    try db.create(table: "kept_offline_new", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("document_id", .integer).notNull()
      // 0: kept on its own; otherwise the kept saved view that keeps it.
      t.column("saved_view_id", .integer).notNull().defaults(to: 0)
      // `timeIntervalSinceReferenceDate` (REAL); the list orders by it.
      t.column("kept_at", .real).notNull()
      t.primaryKey(["server_id", "document_id", "saved_view_id"])
    }
    try db.execute(
      sql: """
        INSERT INTO kept_offline_new (server_id, document_id, saved_view_id, kept_at)
        SELECT server_id, document_id, 0, kept_at FROM kept_offline
        """)
    try db.drop(table: "kept_offline")
    try db.rename(table: "kept_offline_new", to: "kept_offline")
    // Replacing and dropping a view's members.
    try db.create(
      index: "idx_kept_offline_saved_view", on: "kept_offline",
      columns: ["server_id", "saved_view_id"])

    try db.create(table: "kept_offline_view", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("saved_view_id", .integer).notNull()
      // `timeIntervalSinceReferenceDate` (REAL).
      t.column("kept_at", .real).notNull()
      t.primaryKey(["server_id", "saved_view_id"])
    }
  }
}
