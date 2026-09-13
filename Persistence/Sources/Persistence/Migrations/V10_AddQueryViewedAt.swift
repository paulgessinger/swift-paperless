import GRDB

/// Adds `query_meta.viewed_at`: when a list was last put on screen.
///
/// `filled_at` only says a fill paged the list to the end, which is a poor
/// stand-in for "the user was looking at this". A list opened offline, or over a
/// link that dropped mid-fill, was just viewed but has no fill stamp at all. The
/// *Recently browsed* cap decides by this column instead.
///
/// Nullable, with no backfill: nothing recorded when an existing list was last
/// on screen. Reading that as "not recently" costs at most a refill the next
/// time the list is opened.
enum V10_AddQueryViewedAt {
  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "query_meta") { t in
      t.add(column: "viewed_at", .text)
    }
  }
}
