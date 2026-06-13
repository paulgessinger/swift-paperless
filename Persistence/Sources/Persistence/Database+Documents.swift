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

  /// Upsert a batch of documents at a projection level, never downgrading a
  /// row that is already richer (a Tier-1 list fill must not clobber a Tier-2
  /// detail row's level / `detailFetchedAt` / permissions).
  public func upsertDocuments(
    _ domains: [Document], serverID: UUID, projectionLevel: DocumentProjection
  ) throws {
    try writer.write { db in
      for domain in domains {
        try writeDocumentRow(db, domain, serverID: serverID, projectionLevel: projectionLevel)
      }
    }
  }

  /// Single-row write-through (pessimistic mutation), same non-downgrade rule.
  public func upsertDocument(
    _ domain: Document, serverID: UUID, projectionLevel: DocumentProjection
  ) throws {
    try writer.write { db in
      try writeDocumentRow(db, domain, serverID: serverID, projectionLevel: projectionLevel)
    }
  }

  /// Replace (or append to) a cached query's ordered membership and upsert its
  /// document rows in one transaction.
  ///
  /// - `replaceAll: true` (first page of a fill) clears the key's existing
  ///   `query_order` first; subsequent pages pass `false` with an increasing
  ///   `startPosition` so the background fill appends without rewriting earlier
  ///   positions. Document rows go in *before* their `query_order` entries to
  ///   satisfy the composite FK.
  public func writeQueryPage(
    queryKey: QueryKey, serverID: UUID, documents: [Document],
    startPosition: Int, totalCount: UInt?, replaceAll: Bool,
    projectionLevel: DocumentProjection = .metadata
  ) throws {
    try writer.write { db in
      if replaceAll {
        try QueryOrderRow
          .filter(Column("server_id") == serverID && Column("query_key") == queryKey.rawValue)
          .deleteAll(db)
      }
      for (offset, domain) in documents.enumerated() {
        try writeDocumentRow(db, domain, serverID: serverID, projectionLevel: projectionLevel)
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
  /// remote-delete reconcile). The composite FK cascade removes their
  /// `query_order` rows from every cached list at once.
  public func deleteDocuments(serverID: UUID, removedIDs: [UInt]) throws {
    guard !removedIDs.isEmpty else { return }
    try writer.write { db in
      _ =
        try DocumentRecord
        .filter(Column("server_id") == serverID && removedIDs.contains(Column("id")))
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

  /// Non-downgrade single-row upsert: keep the richer of the incoming and
  /// existing projection (level + `detailFetchedAt` + permissions).
  private func writeDocumentRow(
    _ db: GRDB.Database, _ domain: Document, serverID: UUID,
    projectionLevel: DocumentProjection
  ) throws {
    let incoming = DocumentRecord(
      serverId: serverID, domain: domain, projectionLevel: projectionLevel)
    if let existing =
      try DocumentRecord
      .filter(Column("server_id") == serverID && Column("id") == domain.id)
      .fetchOne(db),
      existing.projectionLevel > projectionLevel
    {
      var merged = incoming
      merged.projectionLevel = existing.projectionLevel
      merged.detailFetchedAt = existing.detailFetchedAt
      merged.payload.permissions = existing.payload.permissions
      try merged.upsert(db)
    } else {
      try incoming.upsert(db)
    }
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
