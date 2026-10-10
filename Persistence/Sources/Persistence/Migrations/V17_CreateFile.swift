import GRDB

/// The index of cached document files: one row per blob the `ContentStore`
/// holds, keyed like the store, `(server_id, version_id, kind)`. The row is the
/// source of truth for whether a file exists and what it was fetched against;
/// the directory is repaired to match it, not the other way round.
///
/// `size` and `last_accessed_at` feed the storage budget: originals and
/// archives are evicted least recently accessed first, thumbnails are not
/// access-tracked and never count. `document_id` lets statistics and later
/// passes ask per document without parsing the version. No FK to `document`:
/// like the other detail tables, the rows are dropped explicitly when their
/// version is no longer the live one.
///
/// Regenerable, so `clearCache` wipes it; cascade-deleted with its `server`.
enum V17_CreateFile {
  static let tables = ["file"]

  static func run(_ db: GRDB.Database) throws {
    try db.create(table: "file", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("version_id", .integer).notNull()
      // `original`, `archive` or `thumbnail`.
      t.column("kind", .text).notNull()
      t.column("document_id", .integer).notNull()
      t.column("size", .integer).notNull()
      // The document's `modified` the file was fetched against; NULL for
      // thumbnails, which are keyed by version alone.
      t.column("modified", .real)
      t.column("checksum", .text)
      // `timeIntervalSinceReferenceDate` (REAL), like the other stamps.
      t.column("stored_at", .real).notNull()
      // NULL for thumbnails.
      t.column("last_accessed_at", .real)
      t.primaryKey(["server_id", "version_id", "kind"])
    }
    try db.create(
      index: "idx_file_kind_accessed", on: "file", columns: ["kind", "last_accessed_at"])
    try db.create(index: "idx_file_document", on: "file", columns: ["server_id", "document_id"])
  }
}
