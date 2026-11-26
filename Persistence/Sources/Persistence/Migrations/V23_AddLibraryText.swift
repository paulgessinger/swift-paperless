import GRDB

/// Adds the per-server "text of the entire library" preference to `server`.
///
/// With it on, the text of every document is downloaded and kept, without the
/// document files: enough for the search on the device to cover the whole
/// library at a small fraction of what *Entire library* takes. A sibling of
/// `offline_browsing_mode` and `sync_over_cellular`: durable user config on
/// the connection row, which survives a cache wipe.
///
/// A server in *Entire library* downloads the texts anyway; the column only
/// decides outside it.
enum V23_AddLibraryText {
  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "server") { t in
      t.add(column: "library_text", .integer).notNull().defaults(to: 0)
    }
  }
}
