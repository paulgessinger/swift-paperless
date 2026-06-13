import DataModel
import Foundation
import GRDB

/// Document-cache operations — the only entry points AppShared uses to read or
/// mutate document rows and cached query orderings; GRDB stays sealed inside
/// `Persistence`.
///
/// Reads are pure cache reads (no network — that's the caching repository's
/// `fillQuery`/`sync`). Writes are either a query fill (`writeQueryPage`, the
/// network → DB replay materialization) or a single pessimistic-mutation
/// write-through (`upsertDocument`, `deleteDocuments`).
extension Database {
  // MARK: - Writes

  /// Upsert a batch of documents. Every stored row is the complete object (the
  /// list carries `full_perms`), so this is a straight replace — there is no
  /// projection level to preserve.
  public func upsertDocuments(_ domains: [Document], serverID: UUID) throws {
    try writer.write { db in
      for domain in domains {
        try writeDocumentRow(db, domain, serverID: serverID)
      }
    }
  }

  /// Single-row write-through (pessimistic mutation).
  public func upsertDocument(_ domain: Document, serverID: UUID) throws {
    try writer.write { db in
      try writeDocumentRow(db, domain, serverID: serverID)
    }
  }

  /// Replace (or append to) a cached query's ordered membership and upsert its
  /// document rows in one transaction.
  ///
  /// - `replaceAll: true` (first page of a fill) clears the key's existing
  ///   `query_order` first; subsequent pages pass `false` with an increasing
  ///   `startPosition` so the background fill appends without rewriting earlier
  ///   positions.
  public func writeQueryPage(
    queryKey: QueryKey, serverID: UUID, documents: [Document],
    startPosition: Int, totalCount: UInt?, replaceAll: Bool
  ) throws {
    try writer.write { db in
      if replaceAll {
        try QueryOrderRow
          .filter(Column("server_id") == serverID && Column("query_key") == queryKey.rawValue)
          .deleteAll(db)
      }
      for (offset, domain) in documents.enumerated() {
        try writeDocumentRow(db, domain, serverID: serverID)
        try QueryOrderRow(
          serverId: serverID, queryKey: queryKey.rawValue,
          position: startPosition + offset, remoteId: domain.id
        ).upsert(db)
      }
      try setQueryMeta(
        db, serverID: serverID, queryKey: queryKey,
        totalCount: totalCount, orderStale: false)
    }
  }

  /// Rewrite a cached query's ordered membership from a Tier-0 id list (the
  /// per-saved-view / default-list membership sweep) **without** creating or
  /// modifying `document` rows. Only ids that already have a cached document row
  /// are inserted; ids not yet cached are skipped and surface once R3δ / the next
  /// fill writes their row. (A later change renders such ids as skeleton rows
  /// instead of skipping them.) `position` is compacted over the inserted ids
  /// (gaps from skipped rows are invisible to the ordered window). `totalCount`
  /// records the server's full count for the scrollbar extent, even when some
  /// rows aren't yet locally present.
  public func replaceQueryOrder(
    queryKey: QueryKey, serverID: UUID, orderedIDs: [UInt]
  ) throws {
    try writer.write { db in
      let present =
        try DocumentRecord
        .select(Column("id"), as: UInt.self)
        .filter(Column("server_id") == serverID)
        .fetchSet(db)
      try QueryOrderRow
        .filter(Column("server_id") == serverID && Column("query_key") == queryKey.rawValue)
        .deleteAll(db)
      var position = 0
      for id in orderedIDs where present.contains(id) {
        try QueryOrderRow(
          serverId: serverID, queryKey: queryKey.rawValue,
          position: position, remoteId: id
        ).upsert(db)
        position += 1
      }
      try setQueryMeta(
        db, serverID: serverID, queryKey: queryKey,
        totalCount: UInt(orderedIDs.count), orderStale: false)
    }
  }

  /// Mark every cached query containing `remoteID` order-stale under its active
  /// sort. v1 over-marks (any query the doc is a member of); the ordering
  /// corrects on the next fill / delta.
  public func markQueriesOrderStale(containing remoteID: UInt, serverID: UUID) throws {
    try writer.write { db in
      try db.execute(
        sql: """
          UPDATE query_meta SET order_stale = 1
          WHERE server_id = ? AND query_key IN (
            SELECT DISTINCT query_key FROM query_order
            WHERE server_id = ? AND remote_id = ?)
          """,
        arguments: [serverID, serverID, remoteID])
    }
  }

  /// Delete documents absent from the server's authoritative id set (the
  /// remote-delete reconcile), and prune their `query_order` rows from every
  /// cached list. There is no FK from `query_order` to `document` (a row may be a
  /// skeleton), so the prune is explicit — a removed id must not linger as a
  /// permanent skeleton.
  public func deleteDocuments(serverID: UUID, removedIDs: [UInt]) throws {
    guard !removedIDs.isEmpty else { return }
    try writer.write { db in
      _ =
        try DocumentRecord
        .filter(Column("server_id") == serverID && removedIDs.contains(Column("id")))
        .deleteAll(db)
      _ =
        try QueryOrderRow
        .filter(Column("server_id") == serverID && removedIDs.contains(Column("remote_id")))
        .deleteAll(db)
    }
  }

  // MARK: - Reads (one-shot; observations live in Database+Observe)

  /// A single cached document by `(server, id)`, or `nil` if not cached.
  public func document(serverID: UUID, id: UInt) throws -> Document? {
    try writer.read { db in
      try DocumentRecord
        .filter(Column("server_id") == serverID && Column("id") == id)
        .fetchOne(db)?
        .domain
    }
  }

  /// A single cached document by archive serial number (resolves the ASN
  /// scanner offline via the indexed `asn` column), or `nil` if not cached.
  public func document(serverID: UUID, asn: UInt) throws -> Document? {
    try writer.read { db in
      try DocumentRecord
        .filter(Column("server_id") == serverID && Column("asn") == asn)
        .fetchOne(db)?
        .domain
    }
  }

  /// A window of a cached query's ordered answer: the `query_order ⋈ document`
  /// join, `ORDER BY position` with `LIMIT`/`OFFSET`, so deletion gaps in
  /// `position` are invisible. The observed live form is `observeDocumentPrefix`.
  public func queryDocuments(
    queryKey: QueryKey, serverID: UUID, limit: Int, offset: Int = 0
  ) throws -> [Document] {
    try writer.read { db in
      try DocumentRecord.fetchAll(
        db, sql: Self.queryWindowSQL,
        arguments: [
          serverID, queryKey.rawValue, limit, offset,
        ]
      ).map(\.domain)
    }
  }

  /// Every cached document id for a server — the local set the remote-delete
  /// reconcile diffs against the server's authoritative id set.
  public func allDocumentIDs(serverID: UUID) throws -> Set<UInt> {
    try writer.read { db in
      try DocumentRecord
        .select(Column("id"), as: UInt.self)
        .filter(Column("server_id") == serverID)
        .fetchSet(db)
    }
  }

  /// Server total (scrollbar extent), locally-present count (reflects deletion
  /// gaps), and order-stale flag for a cached query.
  public func queryStatus(queryKey: QueryKey, serverID: UUID) throws -> QueryStatus {
    try writer.read { db in
      try Self.fetchQueryStatus(db, queryKey: queryKey, serverID: serverID)
    }
  }

  // MARK: - Internals (shared with Database+Observe)

  /// The windowed replay join, shared by the one-shot read and the observation.
  static let queryWindowSQL = """
    SELECT d.* FROM query_order q
    JOIN document d ON d.server_id = q.server_id AND d.id = q.remote_id
    WHERE q.server_id = ? AND q.query_key = ?
    ORDER BY q.position
    LIMIT ? OFFSET ?
    """

  static func fetchQueryStatus(
    _ db: GRDB.Database, queryKey: QueryKey, serverID: UUID
  ) throws -> QueryStatus {
    let meta =
      try QueryMetaRow
      .filter(Column("server_id") == serverID && Column("query_key") == queryKey.rawValue)
      .fetchOne(db)
    let localCount =
      try QueryOrderRow
      .filter(Column("server_id") == serverID && Column("query_key") == queryKey.rawValue)
      .fetchCount(db)
    return QueryStatus(
      totalCount: meta?.totalCount, localCount: localCount,
      orderStale: meta?.orderStale ?? false)
  }

  /// Upsert one document row. Every write is the complete object (the list
  /// carries `full_perms`), so this is a straight replace — no merge, no level.
  private func writeDocumentRow(
    _ db: GRDB.Database, _ domain: Document, serverID: UUID
  ) throws {
    try DocumentRecord(serverId: serverID, domain: domain).upsert(db)
  }

  private func setQueryMeta(
    _ db: GRDB.Database, serverID: UUID, queryKey: QueryKey,
    totalCount: UInt?, orderStale: Bool
  ) throws {
    try QueryMetaRow(
      serverId: serverID, queryKey: queryKey.rawValue,
      totalCount: totalCount, orderStale: orderStale, filledAt: Date()
    ).upsert(db)
  }
}
