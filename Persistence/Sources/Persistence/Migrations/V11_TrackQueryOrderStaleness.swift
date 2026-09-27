import GRDB

/// Replaces `query_meta.order_stale` with two counters, and records on each
/// `query_order` row the `modified` date its placement accounts for.
///
/// - `order_generation` counts marks; `order_basis` is the generation the
///   stored order accounts for. The order is stale while they differ, and a
///   rewrite carrying an older basis than the stored one is rejected.
/// - `placed_modified` lets any write of a document row tell whether the
///   document changed since it was placed. `NULL` means unknown (a skeleton).
///   Existing rows take their cached document's date, so only true skeletons
///   start unknown.
enum V11_TrackQueryOrderStaleness {
  static func run(_ db: GRDB.Database) throws {
    // Development builds of #742 ran an earlier v11 that added the counter.
    let hasGeneration = try db.columns(in: "query_meta").contains { $0.name == "order_generation" }
    try db.alter(table: "query_meta") { t in
      if !hasGeneration {
        t.add(column: "order_generation", .integer).notNull().defaults(to: 0)
      }
      t.add(column: "order_basis", .integer).notNull().defaults(to: 0)
    }
    try db.execute(
      sql: """
        UPDATE query_meta SET
          order_basis = order_generation,
          order_generation = order_generation + order_stale
        """)
    try db.alter(table: "query_meta") { t in t.drop(column: "order_stale") }
    try db.alter(table: "query_order") { t in t.add(column: "placed_modified", .real) }
    // `data.modified` is stored as reference-date seconds, like the column.
    try db.execute(
      sql: """
        UPDATE query_order SET placed_modified = (
          SELECT json_extract(d.data, '$.modified') FROM document d
          WHERE d.server_id = query_order.server_id AND d.id = query_order.remote_id)
        """)
  }
}
