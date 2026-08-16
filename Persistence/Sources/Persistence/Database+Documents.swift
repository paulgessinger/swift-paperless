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
  public func upsertDocuments(_ domains: [Document], serverID: UUID) throws(DatabaseError) {
    try wrapping("upsertDocuments") {
      try writer.write { db in
        for domain in domains {
          try writeDocumentRow(db, domain, serverID: serverID)
        }
      }
    }
  }

  /// Single-row write-through (pessimistic mutation).
  public func upsertDocument(_ domain: Document, serverID: UUID) throws(DatabaseError) {
    try wrapping("upsertDocument") {
      try writer.write { db in
        try writeDocumentRow(db, domain, serverID: serverID)
      }
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
  ) throws(DatabaseError) {
    try wrapping("writeQueryPage") {
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
          ).insert(db)
        }
        try setQueryMeta(
          db, serverID: serverID, queryKey: queryKey,
          totalCount: totalCount, orderStale: false)
      }
    }
  }

  /// Rewrite a cached query's ordered membership from a Tier-0 id list (the
  /// per-saved-view / default-list membership sweep) **without** creating or
  /// modifying `document` rows. Ids are written in order, a repeat skipped —
  /// there is no FK to `document`, so an id whose object isn't cached yet
  /// becomes a skeleton row (it gets its object via R3δ / the next fill).
  /// `totalCount` records the server's full count for the scrollbar extent.
  public func replaceQueryOrder(
    queryKey: QueryKey, serverID: UUID, orderedIDs: [UInt]
  ) throws {
    try writer.write { db in
      try QueryOrderRow
        .filter(Column("server_id") == serverID && Column("query_key") == queryKey.rawValue)
        .deleteAll(db)
      for (position, id) in orderedIDs.enumerated() {
        try QueryOrderRow(
          serverId: serverID, queryKey: queryKey.rawValue,
          position: position, remoteId: id
        ).insert(db)
      }
      try setQueryMeta(
        db, serverID: serverID, queryKey: queryKey,
        totalCount: UInt(orderedIDs.count), orderStale: false)
    }
  }

  /// Mark every cached query containing `remoteID` order-stale under its active
  /// sort. v1 over-marks (any query the doc is a member of); the ordering
  /// corrects on the next fill / delta.
  public func markQueriesOrderStale(containing remoteID: UInt, serverID: UUID)
    throws(DatabaseError)
  {
    try wrapping("markQueriesOrderStale") {
      try writer.write { db in
        let containing =
          QueryOrderRow
          .select(Column("query_key"), as: String.self)
          .filter(Column("server_id") == serverID && Column("remote_id") == remoteID)
        try QueryMetaRow
          .filter(Column("server_id") == serverID && containing.contains(Column("query_key")))
          .updateAll(db, Column("order_stale").set(to: true))
      }
    }
  }

  /// Delete documents absent from the server's authoritative id set (the
  /// remote-delete reconcile), and prune their `query_order` rows from every
  /// cached list. There is no FK from `query_order` to `document` (a row may be a
  /// skeleton), so the prune is explicit — a removed id must not linger as a
  /// permanent skeleton.
  public func deleteDocuments(serverID: UUID, removedIDs: [UInt]) throws(DatabaseError) {
    guard !removedIDs.isEmpty else { return }
    try wrapping("deleteDocuments") {
      try writer.write { db in
        try Self.pruneDocumentDetail(db, serverID: serverID, documentIDs: removedIDs)
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
  }

  /// Deletes every `document` row for `serverID` no longer referenced by any
  /// `query_order` row for that server (the anti-join mirror of the
  /// skeleton-read `queryWindowSQL`), plus its detail-cache siblings. Called
  /// when a server's `OfflineBrowsingMode` transitions `.entireLibrary` →
  /// `.recentlyBrowsed`, to reclaim documents that were only cached because of
  /// the proactive fill. "Referenced" today means only `query_order`
  /// membership — pinning (a second future exemption) doesn't exist yet.
  /// Returns the number of documents removed (for logging/tests).
  @discardableResult
  public func pruneUnreferencedDocuments(serverID: UUID) throws -> Int {
    try writer.write { db in
      let orphanIDs = try UInt.fetchAll(
        db,
        sql: """
          SELECT d.id FROM document d
          LEFT JOIN query_order q
            ON q.server_id = d.server_id AND q.remote_id = d.id
          WHERE d.server_id = ? AND q.remote_id IS NULL
          """,
        arguments: [serverID])
      guard !orphanIDs.isEmpty else { return 0 }
      try Self.pruneDocumentDetail(db, serverID: serverID, documentIDs: orphanIDs)
      return
        try DocumentRecord
        .filter(Column("server_id") == serverID && orphanIDs.contains(Column("id")))
        .deleteAll(db)
    }
  }

  /// Drops every cached query's `query_order` / `query_meta` /
  /// `query_sync_error` for `serverID` except `exceptQueryKey` (the default
  /// list). Called ahead of ``pruneUnreferencedDocuments(serverID:)`` on a
  /// `.entireLibrary` → `.recentlyBrowsed` downgrade: saved views proactively
  /// filled while `.entireLibrary` was active should no longer be tracked at
  /// all — they eager-fill again from scratch if reopened (Stage 8), matching
  /// what `.recentlyBrowsed` already does for any other saved view. Returns
  /// the number of `query_order` rows removed.
  @discardableResult
  public func dropQueryOrder(serverID: UUID, exceptQueryKey: QueryKey) throws -> Int {
    try writer.write { db in
      let removed =
        try QueryOrderRow
        .filter(
          Column("server_id") == serverID && Column("query_key") != exceptQueryKey.rawValue
        )
        .deleteAll(db)
      try QueryMetaRow
        .filter(
          Column("server_id") == serverID && Column("query_key") != exceptQueryKey.rawValue
        )
        .deleteAll(db)
      try QuerySyncErrorRecord
        .filter(
          Column("server_id") == serverID && Column("query_key") != exceptQueryKey.rawValue
        )
        .deleteAll(db)
      return removed
    }
  }

  /// Deletes the tail of a cached query's ordered membership beyond
  /// `keepingFirst` positions. Used to cap the default list's `query_order`
  /// on a `.recentlyBrowsed` downgrade. The remaining prefix (positions
  /// `0..<keepingFirst`) still reads correctly via the existing growing-prefix
  /// observation; `query_meta.total_count` is left as the server's true
  /// count, so `QueryStatus.localCount < totalCount` reports the cap the same
  /// way it already reports any other partial local presence. Returns the
  /// number of `query_order` rows removed.
  @discardableResult
  public func truncateQueryOrder(
    serverID: UUID, queryKey: QueryKey, keepingFirst limit: Int
  ) throws -> Int {
    try writer.write { db in
      try QueryOrderRow
        .filter(
          Column("server_id") == serverID && Column("query_key") == queryKey.rawValue
            && Column("position") >= limit
        )
        .deleteAll(db)
    }
  }

  // MARK: - Reads (one-shot; observations live in Database+Observe)

  /// A single cached document by `(server, id)`, or `nil` if not cached.
  public func document(serverID: UUID, id: UInt) throws(DatabaseError) -> Document? {
    try wrapping("document(id:)") {
      try writer.read { db in
        try DocumentRecord
          .filter(Column("server_id") == serverID && Column("id") == id)
          .fetchOne(db)?
          .domain
      }
    }
  }

  /// A single cached document by archive serial number (resolves the ASN
  /// scanner offline via the indexed `asn` column), or `nil` if not cached.
  public func document(serverID: UUID, asn: UInt) throws(DatabaseError) -> Document? {
    try wrapping("document(asn:)") {
      try writer.read { db in
        try DocumentRecord
          .filter(Column("server_id") == serverID && Column("asn") == asn)
          .fetchOne(db)?
          .domain
      }
    }
  }

  /// A window of a cached query's ordered answer: the `query_order ⟕ document`
  /// left join, `ORDER BY position` with `LIMIT`/`OFFSET`. Membership ids whose
  /// object isn't cached come back as ``DocumentEntry/skeleton(id:)``; deletion
  /// gaps in `position` are invisible. The observed live form is
  /// `observeDocumentPrefix`.
  public func queryDocuments(
    queryKey: QueryKey, serverID: UUID, limit: Int, offset: Int = 0
  ) throws(DatabaseError) -> [DocumentEntry] {
    try wrapping("queryDocuments") {
      try writer.read { db in
        try Self.fetchEntries(
          db, serverID: serverID, queryKey: queryKey.rawValue, limit: limit, offset: offset)
      }
    }
  }

  /// Every cached document id for a server — the local set the remote-delete
  /// reconcile diffs against the server's authoritative id set.
  public func allDocumentIDs(serverID: UUID) throws(DatabaseError) -> Set<UInt> {
    try wrapping("allDocumentIDs") {
      try writer.read { db in
        try DocumentRecord
          .select(Column("id"), as: UInt.self)
          .filter(Column("server_id") == serverID)
          .fetchSet(db)
      }
    }
  }

  /// Count of `document` rows cached for a server — a diagnostic surface (the
  /// Offline & Sync screen) so the proactive fill and the downgrade GC's
  /// effect are visible without a debugger.
  public func documentCount(serverID: UUID) throws -> Int {
    try writer.read { db in
      try DocumentRecord.filter(Column("server_id") == serverID).fetchCount(db)
    }
  }

  /// Server total, locally-present count (reflects deletion gaps), and
  /// order-stale flag for a cached query.
  public func queryStatus(queryKey: QueryKey, serverID: UUID) throws(DatabaseError) -> QueryStatus {
    try wrapping("queryStatus") {
      try writer.read { db in
        try Self.fetchQueryStatus(db, queryKey: queryKey, serverID: serverID)
      }
    }
  }

  // MARK: - Internals (shared with Database+Observe)

  /// Map the windowed left-join rows to entries: a present `document` side is
  /// `.loaded`, an absent one (`d.id IS NULL`) is a `.skeleton`. Shared by the
  /// one-shot read and the observation.
  static func fetchEntries(
    _ db: GRDB.Database, serverID: UUID, queryKey: String, limit: Int, offset: Int
  ) throws -> [DocumentEntry] {
    let rows = try Row.fetchAll(
      db, sql: queryWindowSQL, arguments: [serverID, queryKey, limit, offset])
    return try rows.map { row in
      if (row["id"] as UInt?) != nil {
        return .loaded(try DocumentRecord(row: row).domain)
      } else {
        return .skeleton(id: row["remote_id"])
      }
    }
  }

  /// The windowed replay join, shared by the one-shot read and the observation.
  /// LEFT JOIN so a `query_order` id with no `document` row yields a skeleton
  /// (NULL `document` columns); `q.remote_id` always carries the id.
  static let queryWindowSQL = """
    SELECT q.remote_id, d.* FROM query_order q
    LEFT JOIN document d ON d.server_id = q.server_id AND d.id = q.remote_id
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

  /// Deletes the per-document detail-cache siblings (`document_note`,
  /// `file_metadata`) for documents about to be removed from `document`. Must
  /// run **before** the `document` row is deleted, in the same transaction —
  /// `file_metadata` cleanup needs the still-live `versions` list. Neither
  /// detail table has an FK to `document` (only to `server`), so this is
  /// explicit bookkeeping, not a cascade. Shared by `deleteDocuments` and
  /// `pruneUnreferencedDocuments`.
  private static func pruneDocumentDetail(
    _ db: GRDB.Database, serverID: UUID, documentIDs: [UInt]
  ) throws {
    guard !documentIDs.isEmpty else { return }
    try DocumentNoteRecord
      .filter(Column("server_id") == serverID && documentIDs.contains(Column("document_id")))
      .deleteAll(db)

    // Include every recorded version id plus the document's own id (the
    // fallback `file_metadata` key for legacy/un-versioned documents, mirroring
    // `Document.currentVersionID`'s `self.id` fallback).
    let versionIDs =
      try DocumentRecord
      .filter(Column("server_id") == serverID && documentIDs.contains(Column("id")))
      .fetchAll(db)
      .flatMap { record -> [UInt] in
        Array(Set(record.payload.versions.map(\.id) + [record.id]))
      }
    guard !versionIDs.isEmpty else { return }
    try FileMetadataRecord
      .filter(Column("server_id") == serverID && versionIDs.contains(Column("version_id")))
      .deleteAll(db)
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
