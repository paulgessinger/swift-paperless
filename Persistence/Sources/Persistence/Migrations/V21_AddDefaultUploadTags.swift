import GRDB

/// Adds the tags preselected when uploading to a server to `server`.
///
/// A JSON array of tag ids, which only mean something on that server. Like
/// `sync_over_cellular` this is durable user config, so it lives on the
/// connection row: it survives a cache wipe and goes when the server does.
enum V21_AddDefaultUploadTags {
  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "server") { t in
      t.add(column: "default_upload_tags", .text).notNull().defaults(to: "[]")
    }
  }
}
