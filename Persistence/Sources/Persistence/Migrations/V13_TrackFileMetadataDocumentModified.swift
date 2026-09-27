import GRDB

/// Adds `file_metadata.document_modified`: the document's `modified` when its
/// `/metadata/` was fetched. A storage path or filename change moves the file
/// without creating a version, so the filenames in the row change under the
/// same key; a differing `modified` is what reveals it.
///
/// Existing rows for a current version take their document's cached date, so
/// the upgrade doesn't refetch the whole library. Rows for older versions stay
/// `NULL`; nothing reads their date.
enum V13_TrackFileMetadataDocumentModified {
  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "file_metadata") { t in t.add(column: "document_modified", .real) }
    try db.execute(
      sql: """
        UPDATE file_metadata SET document_modified = d.modified
        FROM document d
        WHERE d.server_id = file_metadata.server_id
          AND d.current_version_id = file_metadata.version_id
        """)
  }
}
