import GRDB

/// Drops the document completeness tier and lets `query_order` carry skeletons.
///
/// Once the document list always requests `full_perms`, a stored `document` row is
/// always the complete object, so the `projection_level` / `detail_fetched_at`
/// columns carry nothing — drop them. And to let a `query_order` row reference an
/// id whose object isn't cached yet (a *skeleton*, read via a `LEFT JOIN`), the
/// composite `query_order → document` FK is replaced by a direct
/// `query_order → server` FK: connection-delete still cascades, while per-document
/// deletes prune `query_order` explicitly (see `deleteDocuments`).
///
/// Also creates `server_sync_state`, the per-server sync cursors. It lives here
/// rather than in `V4` because this build carries the first code that reads or
/// writes one — `V4`'s build has no cursors at all, and a migration should not
/// create a table nothing in its own build touches.
///
/// A forward migration (not a `V4` edit) so each shipped stacked build upgrades
/// cleanly — `V4` is owned by the document-cache build and must stay frozen.
enum V6_DropProjectionAndQueryOrderFK {
  /// Regenerable sync state (delta watermark + library coverage), so the
  /// "clear local storage" sweep resets it too — the reconcile re-baselines and
  /// the proactive fill re-runs over the now-empty cache.
  static let tables = ["server_sync_state"]

  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "document") { t in
      t.drop(column: "projection_level")
      t.drop(column: "detail_fetched_at")
    }

    // SQLite can't alter a foreign key in place: create the new shape, copy the
    // rows, and swap. The new `query_order` has no FK to `document` (rows may
    // dangle as skeletons) and a `server` FK for connection-delete cleanup.
    try db.create(table: "query_order_new", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("query_key", .text).notNull()
      t.column("position", .integer).notNull()
      t.column("remote_id", .integer).notNull()
      // Both conflict clauses carried over from V4 — a rebuilt table inherits
      // neither. With the `document` FK gone, the unique key is also the only
      // remaining constraint on `remote_id`.
      t.primaryKey(["server_id", "query_key", "position"], onConflict: .replace)
      t.uniqueKey(["server_id", "query_key", "remote_id"], onConflict: .ignore)
    }
    try db.execute(
      sql: """
        INSERT INTO query_order_new (server_id, query_key, position, remote_id)
        SELECT server_id, query_key, position, remote_id FROM query_order
        """)
    try db.drop(table: "query_order")
    try db.rename(table: "query_order_new", to: "query_order")

    // The reverse-lookup index lived on the old table; recreate it.
    try db.create(
      index: "idx_query_order_doc", on: "query_order",
      columns: ["server_id", "remote_id"])

    // Per-server sync cursors (one row per server). Stored as REAL
    // (`timeIntervalSinceReferenceDate`) for exact round-trips — the delta
    // comparison is precision-sensitive.
    try db.create(table: "server_sync_state", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      // Newest document `modified` applied by the changed-metadata delta (R3δ).
      t.column("delta_watermark", .real)
      // Completed-at of the last successful proactive full-library fill.
      t.column("library_coverage_at", .real)
      t.primaryKey(["server_id"])
    }
  }
}
