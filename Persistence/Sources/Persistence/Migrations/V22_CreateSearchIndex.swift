import GRDB

/// What searching and filtering on the device needs: a full-text index over
/// the stored document texts, and a mark on a cached list that was answered
/// from the device instead of by the server.
///
/// `content_index` has one row per document whose text is indexed, and its
/// `id` is the rowid of that document's entry in `content_fts`. The index
/// follows the `file` table: an entry is written from a `content` file, by
/// ``Database/indexContent(_:)``, and goes when that file's row does. The
/// triggers do the second half, so every path that drops a file row (an
/// eviction, a superseded version, `clearCache`, a removed server) drops the
/// entry with it. `checksum` and `stored_at` are the file row's when it was
/// indexed, which is how a replaced text is told from an indexed one.
///
/// `content_fts` is contentless: the texts already live in the `ContentStore`,
/// and a second copy in the database would double what they take.
/// `contentless_delete` lets a row be removed without its text, and needs
/// SQLite 3.43, which iOS 17 ships. `detail=none` keeps only which documents
/// hold a token, about a third of the default index's size; that rules out
/// phrase queries, which the local search doesn't offer. Titles are not in
/// here: they are a column of `document` and are matched there.
///
/// `query_meta.local_evaluation` is set, to a small JSON description, while a
/// list's order was computed on the device (see `Database+LocalQuery`), and
/// `NULL` for an order the server gave.
enum V22_CreateSearchIndex {
  static func run(_ db: GRDB.Database) throws {
    try db.create(table: "content_index", options: [.strict]) { t in
      // The rowid of the document's `content_fts` entry.
      t.column("id", .integer).primaryKey()
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("document_id", .integer).notNull()
      t.column("version_id", .integer).notNull()
      // The `file` row's, as of indexing.
      t.column("checksum", .text)
      t.column("stored_at", .real).notNull()
      // Characters indexed.
      t.column("length", .integer).notNull()
      t.uniqueKey(["server_id", "document_id"])
    }
    // The trigger on `file` finds its entry by version.
    try db.create(
      index: "idx_content_index_version", on: "content_index",
      columns: ["server_id", "version_id"])

    try db.execute(
      sql: """
        CREATE VIRTUAL TABLE content_fts USING fts5(
          content,
          content='',
          contentless_delete=1,
          detail=none,
          tokenize='unicode61 remove_diacritics 2'
        )
        """)

    try db.execute(
      sql: """
        CREATE TRIGGER content_index_after_delete AFTER DELETE ON content_index
        BEGIN
          DELETE FROM content_fts WHERE rowid = old.id;
        END
        """)
    try db.execute(
      sql: """
        CREATE TRIGGER file_content_after_delete AFTER DELETE ON file
        WHEN old.kind = 'content'
        BEGIN
          DELETE FROM content_index
          WHERE server_id = old.server_id AND version_id = old.version_id;
        END
        """)

    try db.alter(table: "query_meta") { t in
      t.add(column: "local_evaluation", .text)
    }
  }
}
