import GRDB

/// The tags preselected when uploading to a server, one row per
/// `(server, tag)`.
///
/// Configuration, not cache: like `kept_offline` it survives `clearCache`, so
/// it is not in any `tables` list. No FK to `tag`; that row is cache and may be
/// missing until the next sync. Cascade-deleted with its `server`.
enum V21_CreateDefaultUploadTag {
  static func run(_ db: GRDB.Database) throws {
    try db.create(table: "default_upload_tag", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("tag_id", .integer).notNull()
      t.primaryKey(["server_id", "tag_id"])
    }
  }
}
