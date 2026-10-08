import GRDB

/// Drops `server_sync_state.last_successful_sync_at`: `last_reconcile_at` is
/// the scheduler's freshness stamp too.
enum V15_DropLastSuccessfulSync {
  static func run(_ db: GRDB.Database) throws {
    try db.execute(sql: "ALTER TABLE server_sync_state DROP COLUMN last_successful_sync_at")
  }
}
