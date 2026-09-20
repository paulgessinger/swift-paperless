import GRDB

/// Adds `query_meta.order_generation`: how many times a cached list's order has
/// been marked stale.
///
/// `order_stale` on its own cannot say *when* it was set, and a whole-order
/// rewrite needs to know. The rewrite asks the server for the list's answer,
/// waits for it, and then writes that answer and clears the flag — so a mark
/// landing while the request is in flight describes a change the answer in hand
/// predates, and clearing it swallows that change. Nothing re-marks the key
/// afterwards, so the list stays wrong until some other document in it changes
/// or the user pulls to refresh.
///
/// It is invisible without this column precisely because marking is so cheap:
/// it flips this one flag and rewrites no `query_order` row (deliberately, so it
/// cannot garble a fill writing the same key), which also means the rewrite's
/// own write cannot tell that a mark arrived mid-flight. A counter the marker
/// bumps and the rewrite captures before its request gives it something to
/// compare: same value, clear; moved, leave the flag alone.
///
/// Not null, starting at 0 for every existing row, and no backfill is needed —
/// the migrator runs before anything can open a list, so no rewrite can be in
/// flight across the upgrade.
enum V11_AddQueryOrderGeneration {
  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "query_meta") { t in
      t.add(column: "order_generation", .integer).notNull().defaults(to: 0)
    }
  }
}
