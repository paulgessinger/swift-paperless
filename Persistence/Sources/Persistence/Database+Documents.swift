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
///
/// Async only, like every cache table — see the rule in `Database+Connections`.
/// The `static` bodies taking a `GRDB.Database` handle are what in-package
/// seeding and the multi-step transactions (`reclaimAfterDowngrade`) compose
/// from; nothing outside the package can reach the blocking form.
extension Database {
  // MARK: - Writes

  /// Upsert a batch of documents. Every stored row is the complete object (the
  /// list carries `full_perms`), so this is a straight replace — there is no
  /// projection level to preserve.
  public func upsertDocuments(_ domains: [Document], serverID: UUID) async throws {
    try await wrappingAsync("upsertDocuments") {
      try await writer.write { try Self.writeDocumentRows($0, domains, serverID: serverID) }
    }
  }

  static func writeDocumentRows(
    _ db: GRDB.Database, _ domains: [Document], serverID: UUID
  ) throws {
    for domain in domains {
      try writeDocumentRow(db, domain, serverID: serverID)
    }
  }

  /// Single-row write-through (pessimistic mutation).
  public func upsertDocument(_ domain: Document, serverID: UUID) async throws {
    try await wrappingAsync("upsertDocument") {
      try await writer.write { try Self.writeDocumentRow($0, domain, serverID: serverID) }
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
  ) async throws {
    try await wrappingAsync("writeQueryPage") {
      try await writer.write {
        try Self.writeQueryPage(
          $0, queryKey: queryKey, serverID: serverID, documents: documents,
          startPosition: startPosition, totalCount: totalCount, replaceAll: replaceAll)
      }
    }
  }

  private static func writeQueryPage(
    _ db: GRDB.Database, queryKey: QueryKey, serverID: UUID, documents: [Document],
    startPosition: Int, totalCount: UInt?, replaceAll: Bool
  ) throws {
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
      totalCount: totalCount, orderStale: false,
      stamp: replaceAll ? .cleared : .unchanged)
  }

  /// Rewrite a cached query's ordered membership from a Tier-0 id list (the
  /// per-saved-view / default-list membership sweep) **without** creating or
  /// modifying `document` rows. Ids are written in order, a repeat skipped —
  /// there is no FK to `document`, so an id whose object isn't cached yet
  /// becomes a skeleton row (it gets its object via R3δ / the next fill).
  /// `totalCount` records the server's full count for the scrollbar extent.
  public func replaceQueryOrder(
    queryKey: QueryKey, serverID: UUID, orderedIDs: [UInt]
  ) async throws {
    try await wrappingAsync("replaceQueryOrder") {
      try await writer.write {
        try Self.replaceQueryOrder(
          $0, queryKey: queryKey, serverID: serverID, orderedIDs: orderedIDs)
      }
    }
  }

  private static func replaceQueryOrder(
    _ db: GRDB.Database, queryKey: QueryKey, serverID: UUID, orderedIDs: [UInt]
  ) throws {
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
      totalCount: UInt(orderedIDs.count), orderStale: false, stamp: .unchanged)
  }

  /// Mark every cached query containing `remoteID` order-stale under its active
  /// sort. v1 over-marks (any query the doc is a member of); the ordering
  /// corrects on the next fill / delta.
  public func markQueriesOrderStale(containing remoteID: UInt, serverID: UUID) async throws {
    try await wrappingAsync("markQueriesOrderStale") {
      try await writer.write {
        try Self.markOrderStale($0, containing: remoteID, serverID: serverID)
      }
    }
  }

  private static func markOrderStale(
    _ db: GRDB.Database, containing remoteID: UInt, serverID: UUID
  ) throws {
    let containing =
      QueryOrderRow
      .select(Column("query_key"), as: String.self)
      .filter(Column("server_id") == serverID && Column("remote_id") == remoteID)
    try QueryMetaRow
      .filter(Column("server_id") == serverID && containing.contains(Column("query_key")))
      .updateAll(db, Column("order_stale").set(to: true))
  }

  /// Delete documents absent from the server's authoritative id set (the
  /// remote-delete reconcile), and prune their `query_order` rows from every
  /// cached list. There is no FK from `query_order` to `document` (a row may be a
  /// skeleton), so the prune is explicit — a removed id must not linger as a
  /// permanent skeleton.
  public func deleteDocuments(serverID: UUID, removedIDs: [UInt]) async throws {
    guard !removedIDs.isEmpty else { return }
    try await wrappingAsync("deleteDocuments") {
      try await writer.write {
        try Self.removeDocuments($0, serverID: serverID, removedIDs: removedIDs)
      }
    }
  }

  private static func removeDocuments(
    _ db: GRDB.Database, serverID: UUID, removedIDs: [UInt]
  ) throws {
    try pruneDocumentDetail(db, serverID: serverID, documentIDs: removedIDs)
    _ =
      try DocumentRecord
      .filter(Column("server_id") == serverID && removedIDs.contains(Column("id")))
      .deleteAll(db)
    _ =
      try QueryOrderRow
      .filter(Column("server_id") == serverID && removedIDs.contains(Column("remote_id")))
      .deleteAll(db)
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
  public func pruneUnreferencedDocuments(serverID: UUID) async throws -> Int {
    try await wrappingAsync("pruneUnreferencedDocuments") {
      try await writer.write { try Self.pruneUnreferenced($0, serverID: serverID) }
    }
  }

  @discardableResult
  static func pruneUnreferenced(_ db: GRDB.Database, serverID: UUID) throws -> Int {
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
    try pruneDocumentDetail(db, serverID: serverID, documentIDs: orphanIDs)
    return
      try DocumentRecord
      .filter(Column("server_id") == serverID && orphanIDs.contains(Column("id")))
      .deleteAll(db)
  }

  /// Drops every cached query's `query_order` / `query_meta` /
  /// `query_sync_error` for `serverID` except `exceptQueryKey` (the default
  /// list). Called ahead of ``pruneUnreferencedDocuments(serverID:)`` on a
  /// `.entireLibrary` → `.recentlyBrowsed` downgrade: saved views proactively
  /// filled while `.entireLibrary` was active should no longer be tracked at
  /// all — they eager-fill again from scratch if reopened, matching
  /// what `.recentlyBrowsed` already does for any other saved view. Returns
  /// the number of `query_order` rows removed.
  @discardableResult
  public func dropQueryOrder(serverID: UUID, exceptQueryKey: QueryKey) async throws -> Int {
    try await wrappingAsync("dropQueryOrder") {
      try await writer.write {
        try Self.dropQueries($0, serverID: serverID, exceptQueryKey: exceptQueryKey)
      }
    }
  }

  @discardableResult
  static func dropQueries(
    _ db: GRDB.Database, serverID: UUID, exceptQueryKey: QueryKey
  ) throws -> Int {
    let removed =
      try QueryOrderRow
      .filter(Column("server_id") == serverID && Column("query_key") != exceptQueryKey.rawValue)
      .deleteAll(db)
    try QueryMetaRow
      .filter(Column("server_id") == serverID && Column("query_key") != exceptQueryKey.rawValue)
      .deleteAll(db)
    try QuerySyncErrorRecord
      .filter(Column("server_id") == serverID && Column("query_key") != exceptQueryKey.rawValue)
      .deleteAll(db)
    return removed
  }

  /// Deletes the tail of a cached query's ordered membership, keeping the first
  /// `keepingFirst` **rows** in position order. Used to cap the default list's
  /// `query_order` on a `.recentlyBrowsed` downgrade. The remaining prefix still
  /// reads correctly via the existing growing-prefix observation;
  /// `query_meta.total_count` is left as the server's true count, so
  /// `QueryStatus.localCount < totalCount` reports the cap the same way it
  /// already reports any other partial local presence. Returns the number of
  /// `query_order` rows removed.
  ///
  /// Counts rows rather than testing `position < limit`, because positions are
  /// gappy by design (a skipped page-boundary repeat, a deleted document), so a
  /// position test silently keeps fewer rows than asked.
  @discardableResult
  public func truncateQueryOrder(
    serverID: UUID, queryKey: QueryKey, keepingFirst limit: Int
  ) async throws -> Int {
    try await wrappingAsync("truncateQueryOrder") {
      try await writer.write {
        try Self.truncateQuery(
          $0, serverID: serverID, queryKey: queryKey, keepingFirst: limit)
      }
    }
  }

  @discardableResult
  static func truncateQuery(
    _ db: GRDB.Database, serverID: UUID, queryKey: QueryKey, keepingFirst limit: Int
  ) throws -> Int {
    try db.execute(
      sql: """
        DELETE FROM query_order
        WHERE rowid IN (
          SELECT rowid FROM query_order
          WHERE server_id = ? AND query_key = ?
          ORDER BY position
          LIMIT -1 OFFSET ?
        )
        """,
      arguments: [serverID, queryKey.rawValue, limit])
    return db.changesCount
  }

  /// The whole `.entireLibrary` → `.recentlyBrowsed` reclaim in **one**
  /// transaction: drop every tracked query but the default list, cap that list
  /// to `keepingFirst` rows, prune now-unreferenced documents, clear the
  /// coverage marker. Returns the documents reclaimed.
  ///
  /// One transaction because the destructive half runs first: stopping midway
  /// leaves saved views untracked *and* every document still on disk, with
  /// nothing scheduled to finish. The marker is cleared for the same reason — a
  /// later re-upgrade must re-fill rather than trust a stamp over a gutted
  /// cache.
  @discardableResult
  public func reclaimAfterDowngrade(
    serverID: UUID, defaultQueryKey: QueryKey, keepingFirst limit: Int
  ) async throws -> Int {
    try await wrappingAsync("reclaimAfterDowngrade") {
      try await writer.write {
        try Self.reclaim(
          $0, serverID: serverID, defaultQueryKey: defaultQueryKey, keepingFirst: limit)
      }
    }
  }

  private static func reclaim(
    _ db: GRDB.Database, serverID: UUID, defaultQueryKey: QueryKey, keepingFirst limit: Int
  ) throws -> Int {
    try dropQueries(db, serverID: serverID, exceptQueryKey: defaultQueryKey)
    try truncateQuery(db, serverID: serverID, queryKey: defaultQueryKey, keepingFirst: limit)
    let removed = try pruneUnreferenced(db, serverID: serverID)
    try updateSyncState(db, serverID: serverID) { $0.libraryCoverageAt = nil }
    return removed
  }

  // MARK: - Reads (one-shot; observations live in Database+Observe)

  /// A single cached document by `(server, id)`, or `nil` if not cached.
  public func document(serverID: UUID, id: UInt) async throws -> Document? {
    try await wrappingAsync("document(id:)") {
      try await writer.read { try Self.fetchDocument($0, serverID: serverID, id: id) }
    }
  }

  private static func fetchDocument(
    _ db: GRDB.Database, serverID: UUID, id: UInt
  ) throws -> Document? {
    try DocumentRecord
      .filter(Column("server_id") == serverID && Column("id") == id)
      .fetchOne(db)?
      .domain
  }

  /// A single cached document by archive serial number (resolves the ASN
  /// scanner offline via the indexed `asn` column), or `nil` if not cached.
  public func document(serverID: UUID, asn: UInt) async throws -> Document? {
    try await wrappingAsync("document(asn:)") {
      try await writer.read { try Self.fetchDocument($0, serverID: serverID, asn: asn) }
    }
  }

  private static func fetchDocument(
    _ db: GRDB.Database, serverID: UUID, asn: UInt
  ) throws -> Document? {
    try DocumentRecord
      .filter(Column("server_id") == serverID && Column("asn") == asn)
      .fetchOne(db)?
      .domain
  }

  /// A window of a cached query's ordered answer: the `query_order ⟕ document`
  /// left join, `ORDER BY position` with `LIMIT`/`OFFSET`. Membership ids whose
  /// object isn't cached come back as ``DocumentEntry/skeleton(id:)``; deletion
  /// gaps in `position` are invisible. The observed live form is
  /// `observeDocumentPrefix`.
  public func queryDocuments(
    queryKey: QueryKey, serverID: UUID, limit: Int, offset: Int = 0
  ) async throws -> [DocumentEntry] {
    try await wrappingAsync("queryDocuments") {
      try await writer.read {
        try Self.fetchEntries(
          $0, serverID: serverID, queryKey: queryKey.rawValue, limit: limit, offset: offset)
      }
    }
  }

  /// Every cached document id for a server — the local set the remote-delete
  /// reconcile diffs against the server's authoritative id set.
  public func allDocumentIDs(serverID: UUID) async throws -> Set<UInt> {
    try await wrappingAsync("allDocumentIDs") {
      try await writer.read { try Self.fetchAllDocumentIDs($0, serverID: serverID) }
    }
  }

  private static func fetchAllDocumentIDs(
    _ db: GRDB.Database, serverID: UUID
  ) throws -> Set<UInt> {
    try DocumentRecord
      .select(Column("id"), as: UInt.self)
      .filter(Column("server_id") == serverID)
      .fetchSet(db)
  }

  /// Count of `document` rows cached for a server — a diagnostic surface (the
  /// Offline & Sync screen) so the proactive fill and the downgrade GC's
  /// effect are visible without a debugger.
  public func documentCount(serverID: UUID) async throws -> Int {
    try await wrappingAsync("documentCount") {
      try await writer.read {
        try DocumentRecord.filter(Column("server_id") == serverID).fetchCount($0)
      }
    }
  }

  /// Record that the fill owning this query paged it all the way to the end, so
  /// the cached order is the query's complete membership.
  ///
  /// Called only on a clean finish — not on cancellation, not on a failed page.
  /// The absence of the stamp is what tells the next pass the order is truncated
  /// and has to be redone; without it an interrupted fill was silently
  /// indistinguishable from a complete one.
  public func markQueryFillComplete(queryKey: QueryKey, serverID: UUID) async throws {
    try await wrappingAsync("markQueryFillComplete") {
      try await writer.write {
        try Self.stampFillComplete($0, queryKey: queryKey, serverID: serverID)
      }
    }
  }

  private static func stampFillComplete(
    _ db: GRDB.Database, queryKey: QueryKey, serverID: UUID
  ) throws {
    let meta =
      try QueryMetaRow
      .filter(Column("server_id") == serverID && Column("query_key") == queryKey.rawValue)
      .fetchOne(db)
    try setQueryMeta(
      db, serverID: serverID, queryKey: queryKey,
      totalCount: meta?.totalCount, orderStale: meta?.orderStale ?? false,
      stamp: .completed)
  }

  /// When this query's order was last filled to completion, or `nil` if it never
  /// was (or was truncated since by a page-1 replace).
  public func queryFillCompletedAt(queryKey: QueryKey, serverID: UUID) async throws -> Date? {
    try await wrappingAsync("queryFillCompletedAt") {
      try await writer.read { try Self.fetchFilledAt($0, queryKey: queryKey, serverID: serverID) }
    }
  }

  private static func fetchFilledAt(
    _ db: GRDB.Database, queryKey: QueryKey, serverID: UUID
  ) throws -> Date? {
    try QueryMetaRow
      .filter(Column("server_id") == serverID && Column("query_key") == queryKey.rawValue)
      .fetchOne(db)?.filledAt
  }

  /// Server total, locally-present count (reflects deletion gaps), and
  /// order-stale flag for a cached query.
  public func queryStatus(queryKey: QueryKey, serverID: UUID) async throws -> QueryStatus {
    try await wrappingAsync("queryStatus") {
      try await writer.read {
        try Self.fetchQueryStatus($0, queryKey: queryKey, serverID: serverID)
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
  private static func writeDocumentRow(
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

  /// What a `query_meta` write does to the `filled_at` stamp.
  ///
  /// The stamp means *"the fill that owns this key paged it to the end"*. It
  /// used to be set on every `writeQueryPage`, i.e. it meant "a page was
  /// written" — which is why a fill interrupted on page 2 left a 250-row order
  /// carrying the server's full 3000 as `total_count` and a fresh `filled_at`,
  /// indistinguishable from a complete one.
  enum FillStamp {
    /// Page 1 of a fill: `replaceAll` has just deleted the key's whole order,
    /// so it is known-incomplete until the fill says otherwise.
    case cleared
    /// A later page, or a membership rewrite — leave whatever is recorded.
    case unchanged
    /// The fill's paging loop reached the end of the query.
    case completed
  }

  private static func setQueryMeta(
    _ db: GRDB.Database, serverID: UUID, queryKey: QueryKey,
    totalCount: UInt?, orderStale: Bool, stamp: FillStamp
  ) throws {
    let filledAt: Date?
    switch stamp {
    case .cleared: filledAt = nil
    case .completed: filledAt = Date()
    case .unchanged:
      // A record `upsert` rewrites every column, so carrying the stamp forward
      // has to be explicit. Same transaction as the caller's write, so no other
      // writer can slip in between the read and the upsert.
      filledAt =
        try QueryMetaRow
        .filter(Column("server_id") == serverID && Column("query_key") == queryKey.rawValue)
        .fetchOne(db)?.filledAt
    }
    try QueryMetaRow(
      serverId: serverID, queryKey: queryKey.rawValue,
      totalCount: totalCount, orderStale: orderStale, filledAt: filledAt
    ).upsert(db)
  }
}
