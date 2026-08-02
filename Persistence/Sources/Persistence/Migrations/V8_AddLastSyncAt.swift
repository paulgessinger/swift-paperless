import GRDB

/// Adds `last_sync_at` to `server_sync_state`: when this server's element sync
/// last completed successfully (`timeIntervalSinceReferenceDate`, REAL, like
/// the other cursors).
///
/// Stage 11 (background sync) needs a *persisted* per-server freshness stamp:
/// a cold background launch has no in-memory throttle map, so stalest-first
/// sweep ordering must come from the DB, and the Offline & Sync screen shows
/// it as the honest "fresh as of last successful sync" surface. Regenerable
/// like its siblings — the row is wiped by `clearCache` and cascade-deleted
/// with its `server`.
enum V8_AddLastSyncAt {
  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "server_sync_state") { t in
      t.add(column: "last_sync_at", .real)
    }
  }
}
