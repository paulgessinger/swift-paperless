import GRDB

/// Per-document detail-cache tables (Stage 8 follow-up) — the two Tier-2
/// sub-resources that don't ride the `document` row's `data` blob because they
/// have different keys and lifecycles:
///
/// - `document_note` — one row per `(server_id, document_id)`, holding the whole
///   notes list as a JSON `data` blob. **Mutable**: each fetch / create / delete
///   replaces the row, so it's keyed by document id (not version). The inline
///   `notes` array on the document object is count-only by design (its shape
///   changed across backends), so the stable content source is the separate
///   `/notes/` endpoint cached here.
/// - `file_metadata` — one row per `(server_id, version_id)`, holding the
///   `/metadata/` sub-resource (checksums, sizes, mime, parsed item lists) as a
///   JSON `data` blob. **Immutable per file version** (like `ContentStore`), so
///   keying by version means a cached copy never goes stale until the version
///   changes.
///
/// Both FK-reference `server(id)` with `ON DELETE CASCADE`, so removing a
/// connection tears down its detail cache along with the rest.
enum V5_CreateDocumentDetailCache {
  /// Both detail-cache tables, for the blanket "clear local storage" sweep.
  static let tables = ["document_note", "file_metadata"]

  static func run(_ db: GRDB.Database) throws {
    try db.create(table: "document_note", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("document_id", .integer).notNull()
      t.column("data", .text).notNull()
      t.primaryKey(["server_id", "document_id"])
    }

    try db.create(table: "file_metadata", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("version_id", .integer).notNull()
      t.column("data", .text).notNull()
      t.primaryKey(["server_id", "version_id"])
    }
  }
}
