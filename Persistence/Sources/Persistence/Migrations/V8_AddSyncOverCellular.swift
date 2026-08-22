import GRDB

/// Adds the per-server "sync over cellular" preference to `server`.
///
/// Sibling of `offline_browsing_mode` from `V1`: durable user config, not
/// regenerable sync state, so it lives on the connection row and survives a
/// cache wipe. Defaults to `0` — proactive downloading stays Wi-Fi-only unless
/// the user opts a server in, which is what the previous hard-coded gate did.
///
/// Note this governs only the *proactive* sweeps (library fill, detail fill,
/// reconcile). Interactive work the user asked for is never gated on it.
enum V8_AddSyncOverCellular {
  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "server") { t in
      t.add(column: "sync_over_cellular", .integer).notNull().defaults(to: 0)
    }
  }
}
