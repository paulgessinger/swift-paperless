import GRDB

/// Document-metadata cache tables.
///
/// Three tables, three jobs:
///
/// - `document` — one row per `(server_id, id)`, query-independent. A document
///   that appears in many lists still has a single metadata row here. Indexed
///   columns carry what the join/lookups need (`title`, `asn`, the completeness
///   marker `projection_level` / `detail_fetched_at`); the long tail lives in the
///   `data` JSON blob, exactly like the element cache.
/// - `query_order` — one row per `(server_id, query_key, position)` → `remote_id`.
///   Pure membership + ordering: replaying a cached list is a join through this
///   table (`ORDER BY position`), so the server's exact order is preserved and
///   ad-hoc offline filtering is intentionally unsupported. The composite FK to
///   `document` with `ON DELETE CASCADE` is load-bearing: deleting one document
///   row drops it from *every* list at once.
/// - `query_meta` — one row per `(server_id, query_key)`: server-reported
///   `total_count` (the server's count, which survives deletion gaps) and an
///   `order_stale` flag set by mutations under the active sort.
///
/// Every table FK-references `server(id)` with `ON DELETE CASCADE`, so removing a
/// connection tears down its whole document cache too.
///
/// Per-server *sync cursors* deliberately live elsewhere: nothing in this build
/// keeps one, so the table that holds them is created by the migration that
/// introduces the first reader rather than sitting here unused.
enum V4_CreateDocumentCache {
  /// All document-cache tables. Listed `query_order`-before-`document` so a
  /// blanket clear deletes children before parents (the cascade makes order
  /// immaterial for correctness, but explicit is cheaper than relying on it).
  static let tables = ["query_order", "query_meta", "document"]

  static func run(_ db: GRDB.Database) throws {
    try db.create(table: "document", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("id", .integer).notNull()
      t.column("title", .text).notNull()
      // Promoted out of the JSON blob so the ASN scanner can resolve
      // `WHERE asn = ?` against an index.
      t.column("asn", .integer)
      // Completeness marker: 0 id-only / 1 renderable / 2 detail.
      t.column("projection_level", .integer).notNull()
      // Set when Tier-2 detail lands; distinguishes "null on the server" from
      // "not fetched yet". Stored as text (GRDB's Date encoding) for STRICT.
      t.column("detail_fetched_at", .text)
      t.column("data", .text).notNull()
      t.primaryKey(["server_id", "id"])
    }

    // Serves `document(serverID:asn:)` (the ASN-scanner lookup). Partial: most
    // documents have no ASN, so rows with `asn IS NULL` don't bloat the index.
    try db.create(
      index: "idx_document_asn", on: "document",
      columns: ["server_id", "asn"],
      condition: Column("asn") != nil)

    try db.create(table: "query_order", options: [.strict]) { t in
      t.column("server_id", .blob).notNull()
      t.column("query_key", .text).notNull()
      t.column("position", .integer).notNull()
      t.column("remote_id", .integer).notNull()
      // `.replace` so a second writer claiming a position overwrites rather than
      // aborting the whole page: the list fill and the proactive library fill can
      // target the same query, and a thrown write kills the rest of the fill.
      t.primaryKey(["server_id", "query_key", "position"], onConflict: .replace)

      // A document appears at most once per query. The server can repeat one
      // across adjacent pages when an insert/delete shifts the page offsets;
      // `.ignore` skips the second placement (leaving a `position` gap, which
      // the ordered replay tolerates) while a `position` collision still aborts.
      t.uniqueKey(["server_id", "query_key", "remote_id"], onConflict: .ignore)

      // Drop a list entry whenever its document row is deleted (the remote-delete
      // cascade). Parent is `document`'s `(server_id, id)` primary key.
      t.foreignKey(
        ["server_id", "remote_id"], references: "document",
        columns: ["server_id", "id"], onDelete: .cascade)
    }

    // Reverse lookup: "which queries contain this document?" — used by the
    // mutation order-stale marking and to back the FK cascade efficiently. The
    // forward/ordered scan (`WHERE server_id=? AND query_key=? ORDER BY position`)
    // is already served by the primary-key index.
    try db.create(
      index: "idx_query_order_doc", on: "query_order",
      columns: ["server_id", "remote_id"])

    try db.create(table: "query_meta", options: [.strict]) { t in
      t.column("server_id", .blob)
        .notNull()
        .references("server", onDelete: .cascade)
      t.column("query_key", .text).notNull()
      t.column("total_count", .integer)
      t.column("order_stale", .integer).notNull().defaults(to: 0)
      t.column("filled_at", .text)
      t.primaryKey(["server_id", "query_key"])
    }
  }
}
