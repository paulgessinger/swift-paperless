import GRDB

/// Adds per-server freshness stamps to `server_sync_state`: `last_reconcile_at`
/// ("Last refreshed") and `last_successful_sync_at` (the scheduler's throttle).
enum V14_PersistSyncFreshness {
  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "server_sync_state") { t in
      t.add(column: "last_reconcile_at", .real)
      t.add(column: "last_successful_sync_at", .real)
    }
  }
}
