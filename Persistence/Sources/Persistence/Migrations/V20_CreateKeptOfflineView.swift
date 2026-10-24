import GRDB

/// The saved views the user keeps on the device: every document a kept view
/// lists is kept offline while it is listed.
///
/// Configuration, not cache, like `kept_offline`: it survives `clearCache` and
/// cascades with its `server`. Keyed by the saved view's id, so a view edited on
/// the server stays kept. `query_key` is the `QueryKey` the view's membership is
/// stored under in `query_order`; the protections join on it, and the element
/// sync rewrites it when the view's filter or sort changes. No FK to
/// `saved_view`, which is cache.
enum V20_CreateKeptOfflineView {
  static func run(_ db: GRDB.Database) throws {
    try db.create(table: "kept_offline_view", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("saved_view_id", .integer).notNull()
      t.column("query_key", .text).notNull()
      // `timeIntervalSinceReferenceDate` (REAL).
      t.column("kept_at", .real).notNull()
      t.primaryKey(["server_id", "saved_view_id"])
    }
  }
}
