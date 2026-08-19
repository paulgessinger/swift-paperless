import GRDB

/// Promotes two values out of `document.data` into real columns, for the same
/// reason `V4` promoted `asn`: they are *queried*, and a JSON blob in a `TEXT`
/// column can't be.
///
/// The detail fill asks "which documents still need notes?" and "which are
/// missing file metadata for their current version?" on every foreground, over
/// the whole table. Expressed against the blob those need `json_extract` and
/// `json_each`, which parse every row's JSON on every run and can use no index —
/// measured at ~15 ms and ~19 ms respectively over 20k documents on a desktop
/// with a much newer SQLite than iOS 17 ships, on the main actor. With the
/// columns the same queries are ~1.6 ms and ~6.5 ms.
///
/// `JSONB` would have made the blob itself cheap to query, but it needs SQLite
/// 3.45 and iOS 17 ships 3.43.
///
/// **Invariant:** both columns are derived from `payload` and written only by
/// `DocumentRecord.init(serverId:domain:)`, which is the single place a row is
/// constructed. They are a denormalisation for querying, never an independent
/// source of truth — `domain` still reads notes count and versions from the
/// payload.
enum V9_PromoteDocumentQueryColumns {
  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "document") { t in
      t.add(column: "notes_count", .integer).notNull().defaults(to: 0)
      // `Document.currentVersionID`: highest version id, falling back to the
      // document id when a document has no versions.
      t.add(column: "current_version_id", .integer).notNull().defaults(to: 0)
    }

    // Backfill from the blob. This is the one place the JSON path is still
    // walked, and it runs once.
    try db.execute(
      sql: """
        UPDATE document SET
          notes_count = COALESCE(json_extract(data, '$.notesCount'), 0),
          current_version_id = COALESCE(
            (SELECT MAX(CAST(json_extract(v.value, '$.id') AS INTEGER))
             FROM json_each(document.data, '$.versions') v),
            id)
        """)

    // Serves the "needs a notes fetch" predicate. No matching index for
    // `current_version_id`: that predicate is an anti-join against
    // `file_metadata`, which is already keyed by `(server_id, version_id)`.
    try db.create(
      index: "idx_document_notes_count", on: "document",
      columns: ["server_id", "notes_count"])
  }
}
