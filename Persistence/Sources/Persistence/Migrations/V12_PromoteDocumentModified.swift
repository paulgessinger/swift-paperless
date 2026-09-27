import GRDB

/// Promotes `modified` out of `document.data` into a real column, as `V9` did
/// for `notes_count`: a membership rewrite places each `query_order` row under
/// its document's `modified`, and reading it from the blob parsed the whole
/// JSON once per row.
///
/// The column replaces the payload's copy. Stored as reference-date seconds,
/// which is also how the blob encoded it, so the backfill copies the value as
/// is.
enum V12_PromoteDocumentModified {
  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "document") { t in t.add(column: "modified", .real) }
    try db.execute(sql: "UPDATE document SET modified = json_extract(data, '$.modified')")
  }
}
