import GRDB

/// One freshness stamp per server: `last_reconcile_at` becomes
/// `last_refreshed_at`, matching "Last refreshed", and
/// `last_successful_sync_at` is dropped. The scheduler reads the remaining one.
enum V15_SingleFreshnessStamp {
  static func run(_ db: GRDB.Database) throws {
    try db.execute(
      sql: "ALTER TABLE server_sync_state RENAME COLUMN last_reconcile_at TO last_refreshed_at")
    try db.execute(sql: "ALTER TABLE server_sync_state DROP COLUMN last_successful_sync_at")
  }
}
