import GRDB

/// First schema: the `server` table (one row per configured paperless
/// connection).
///
/// The `active_server` pointer is deliberately not a column or table here —
/// `ConnectionManager` keeps the active connection id in app-group
/// `UserDefaults` for free cross-process syncing with the Share Extension.
enum V1_CreateServer {
  static func run(_ db: GRDB.Database) throws {
    try db.create(table: "server", options: [.strict]) { t in
      t.primaryKey("id", .blob)
      t.column("url", .text).notNull()
      t.column("friendly_name", .text)
      t.column("identity", .text)
      t.column("user", .text).notNull()
      t.column("extra_headers", .text).notNull().defaults(to: "[]")
      t.column("needs_auth", .integer).notNull().defaults(to: 0)
      // Per-server offline browsing scope (durable user config; survives a
      // cache wipe). Raw value of AppShared's `OfflineBrowsingMode`.
      t.column("offline_browsing_mode", .text).notNull().defaults(to: "recentlyBrowsed")
    }
  }
}
