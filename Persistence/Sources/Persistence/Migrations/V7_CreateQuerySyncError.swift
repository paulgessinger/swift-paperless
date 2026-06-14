import GRDB

/// Records the most recent *proactive-sync* failure for a cached query, so the
/// app can warn that a saved view (or the default list) couldn't be filled for
/// offline use.
///
/// One row per `(server_id, query_key)` — the same key `query_order` /
/// `query_meta` use — written when a view's fill or membership sweep is rejected
/// (e.g. an advanced full-text query the server won't run) and deleted on the
/// next success. It is *not* part of `query_meta` because a view can fail on its
/// very first page, before any `query_meta` row exists. `saved_view_name` is
/// stored so the UI can label the row without resolving the opaque key back to a
/// view (a `nil` name denotes the default list). Regenerable, so `clearCache`
/// wipes it; cascade-deleted with its `server`.
enum V7_CreateQuerySyncError {
  static let tables = ["query_sync_error"]

  static func run(_ db: GRDB.Database) throws {
    try db.create(table: "query_sync_error", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("query_key", .text).notNull()
      // The saved view's display name, or NULL for the default list.
      t.column("saved_view_name", .text)
      t.column("message", .text).notNull()
      // `timeIntervalSinceReferenceDate` (REAL), like the other sync cursors.
      t.column("failed_at", .real).notNull()
      t.primaryKey(["server_id", "query_key"])
    }
  }
}
