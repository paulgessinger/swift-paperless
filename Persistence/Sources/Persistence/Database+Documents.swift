import DataModel
import Foundation
import GRDB

/// Document-cache operations — the only entry points AppShared uses to read or
/// mutate document rows and cached query orderings; GRDB stays sealed inside
/// `Persistence`.
///
/// Reads are pure cache reads (no network — that's the caching repository's
/// `fillQuery`/`sync`). Writes are either a query fill (`replaceQueryPage` /
/// `appendQueryPage`, the network → DB replay materialization) or a single
/// pessimistic-mutation write-through (`upsertDocument`, `deleteDocuments`).
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
      try await writer.write { _ = try Self.writeDocumentRows($0, domains, serverID: serverID) }
    }
  }

  @discardableResult
  static func writeDocumentRows(
    _ db: GRDB.Database, _ domains: [Document], serverID: UUID
  ) throws -> Int {
    try domains.reduce(0) { $0 + (try writeDocumentRow(db, $1, serverID: serverID)) }
  }

  /// Apply a page of the changed-documents delta (R3δ): upsert the documents,
  /// drop their cached notes, and mark stale the cached lists they may have
  /// moved in, in one transaction. Returns how many lists were newly marked.
  ///
  /// Notes are dropped because a note edit bumps `modified` and the delta can't
  /// tell which field changed. One transaction so a note write-through can't
  /// land between the upsert and the drop and be deleted by it.
  ///
  /// Besides the placement check every document row write does, a list holding
  /// a document as a skeleton is marked too: its position came from a copy the
  /// cache never saw, and the delta returning it means it changed recently.
  @discardableResult
  public func applyChangedDocuments(
    _ domains: [Document], serverID: UUID
  ) async throws -> Int {
    guard !domains.isEmpty else { return 0 }
    return try await wrappingAsync("applyChangedDocuments") {
      try await writer.write { db in
        let ids = domains.map(\.id)
        let cached = try Set(
          DocumentRecord
            .select(Column("id"), as: UInt.self)
            .filter(Column("server_id") == serverID && ids.contains(Column("id")))
            .fetchAll(db))
        let skeletons = ids.filter { !cached.contains($0) }

        var marked = try Self.writeDocumentRows(db, domains, serverID: serverID)
        try Self.dropNotes(serverID: serverID, documentIDs: ids, db)
        marked += try Self.markOrderStale(
          db, keys: Self.queryKeys(listingAnyOf: skeletons, serverID: serverID),
          serverID: serverID)
        return marked
      }
    }
  }

  /// Single-row write-through (pessimistic mutation).
  public func upsertDocument(_ domain: Document, serverID: UUID) async throws {
    try await wrappingAsync("upsertDocument") {
      try await writer.write { _ = try Self.writeDocumentRow($0, domain, serverID: serverID) }
    }
  }

  /// Page 1 of a fill: replace a cached query's order with `documents` and
  /// upsert their rows, in one transaction.
  ///
  /// `basis` is the key's generation captured before the page was requested.
  /// - Returns: `false`, writing nothing, if a rewrite with a newer basis has
  ///   already landed.
  @discardableResult
  public func replaceQueryPage(
    queryKey: QueryKey, serverID: UUID, documents: [Document], totalCount: UInt?,
    basis: QueryOrderGeneration
  ) async throws -> Bool {
    try await wrappingAsync("replaceQueryPage") {
      try await writer.write { db in
        guard try Self.accepts(basis, db, queryKey: queryKey, serverID: serverID) else {
          return false
        }
        try Self.deleteQueryOrder(db, queryKey: queryKey, serverID: serverID)
        try Self.writeQueryPage(
          db, queryKey: queryKey, serverID: serverID, documents: documents, startPosition: 0)
        try Self.setQueryMeta(
          db, serverID: serverID, queryKey: queryKey, totalCount: totalCount,
          basis: basis, stamp: .cleared)
        return true
      }
    }
  }

  /// A later page of a fill: append `documents` at `startPosition` and upsert
  /// their rows. Leaves the staleness alone — marks since page 1 still apply to
  /// the rows it wrote.
  public func appendQueryPage(
    queryKey: QueryKey, serverID: UUID, documents: [Document],
    startPosition: Int, totalCount: UInt?
  ) async throws {
    try await wrappingAsync("appendQueryPage") {
      try await writer.write { db in
        try Self.writeQueryPage(
          db, queryKey: queryKey, serverID: serverID, documents: documents,
          startPosition: startPosition)
        try Self.setQueryMeta(
          db, serverID: serverID, queryKey: queryKey, totalCount: totalCount,
          basis: nil, stamp: .unchanged)
      }
    }
  }

  private static func writeQueryPage(
    _ db: GRDB.Database, queryKey: QueryKey, serverID: UUID, documents: [Document],
    startPosition: Int
  ) throws {
    for (offset, domain) in documents.enumerated() {
      // Placed before the row is written, so the row's own placement check
      // doesn't mark this key.
      try QueryOrderRow(
        serverId: serverID, queryKey: queryKey.rawValue,
        position: startPosition + offset, remoteId: domain.id,
        placedModified: domain.modified?.timeIntervalSinceReferenceDate
      ).insert(db)
      try writeDocumentRow(db, domain, serverID: serverID)
    }
  }

  /// Rewrite a cached query's ordered membership from a Tier-0 id list (the
  /// per-saved-view / default-list membership sweep) **without** creating or
  /// modifying `document` rows. Ids are written in order, a repeat skipped —
  /// there is no FK to `document`, so an id whose object isn't cached yet
  /// becomes a skeleton row (it gets its object via R3δ / the next fill).
  /// `totalCount` records the server's full count for the scrollbar extent.
  ///
  /// Each row is placed under the cached document's `modified`.
  /// - Returns: `false`, writing nothing, if a rewrite with a newer basis has
  ///   already landed.
  @discardableResult
  public func replaceQueryOrder(
    queryKey: QueryKey, serverID: UUID, orderedIDs: [UInt], basis: QueryOrderGeneration
  ) async throws -> Bool {
    try await wrappingAsync("replaceQueryOrder") {
      try await writer.write { db in
        guard try Self.accepts(basis, db, queryKey: queryKey, serverID: serverID) else {
          return false
        }
        try Self.deleteQueryOrder(db, queryKey: queryKey, serverID: serverID)
        // `data.modified` is stored as reference-date seconds, the same value
        // `placed_modified` holds.
        let insert = try db.cachedStatement(
          sql: """
            INSERT INTO query_order (server_id, query_key, position, remote_id, placed_modified)
            VALUES (?, ?, ?, ?,
              (SELECT json_extract(data, '$.modified') FROM document WHERE server_id = ? AND id = ?))
            """)
        for (position, id) in orderedIDs.enumerated() {
          try insert.execute(arguments: [
            serverID, queryKey.rawValue, position, id, serverID, id,
          ])
        }
        try Self.setQueryMeta(
          db, serverID: serverID, queryKey: queryKey, totalCount: UInt(orderedIDs.count),
          basis: basis, stamp: .unchanged)
        return true
      }
    }
  }

  private static func deleteQueryOrder(
    _ db: GRDB.Database, queryKey: QueryKey, serverID: UUID
  ) throws {
    try QueryOrderRow
      .filter(Column("server_id") == serverID && Column("query_key") == queryKey.rawValue)
      .deleteAll(db)
  }

  /// Whether a rewrite based on `basis` is at least as new as the stored order.
  private static func accepts(
    _ basis: QueryOrderGeneration, _ db: GRDB.Database, queryKey: QueryKey, serverID: UUID
  ) throws -> Bool {
    basis.value >= (try fetchQueryMeta(db, queryKey: queryKey, serverID: serverID)?.orderBasis ?? 0)
  }

  /// The key's mark counter, to be captured by a whole-order rewrite before its
  /// request and passed to its write as `basis`.
  public func queryOrderGeneration(
    queryKey: QueryKey, serverID: UUID
  ) async throws -> QueryOrderGeneration {
    try await wrappingAsync("queryOrderGeneration") {
      try await writer.read { db in
        QueryOrderGeneration(
          try Self.fetchQueryMeta(db, queryKey: queryKey, serverID: serverID)?.orderGeneration
            ?? 0)
      }
    }
  }

  /// Mark every cached query containing `remoteID` order-stale. Over-marks: any
  /// query the document is a member of.
  public func markQueriesOrderStale(containing remoteID: UInt, serverID: UUID) async throws {
    try await wrappingAsync("markQueriesOrderStale") {
      try await writer.write {
        _ = try Self.markOrderStale(
          $0, keys: Self.queryKeys(listingAnyOf: [remoteID], serverID: serverID),
          serverID: serverID)
      }
    }
  }

  private static func queryKeys(
    listingAnyOf remoteIDs: [UInt], serverID: UUID
  ) -> QueryInterfaceRequest<String> {
    QueryOrderRow
      .select(Column("query_key"), as: String.self)
      .filter(Column("server_id") == serverID && remoteIDs.contains(Column("remote_id")))
  }

  /// Bump the mark counter of every key in `keys`, and return how many were not
  /// already stale.
  @discardableResult
  private static func markOrderStale(
    _ db: GRDB.Database, keys: QueryInterfaceRequest<String>, serverID: UUID
  ) throws -> Int {
    let marked =
      QueryMetaRow
      .filter(Column("server_id") == serverID && keys.contains(Column("query_key")))
    let newlyStale =
      try marked
      .filter(Column("order_generation") == Column("order_basis"))
      .fetchCount(db)
    try marked.updateAll(
      db, Column("order_generation").set(to: Column("order_generation") + 1))
    return newlyStale
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
  /// already reports any other partial local presence. `filled_at` is kept too
  /// (the reachability LRU ranks on it); `QueryStatus.isComplete` still reads
  /// `false` afterwards, because the order no longer reaches the total. Returns
  /// the number of `query_order` rows removed.
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

  /// Which of `ids` have no cached `document` row, in order, without repeats.
  public func documentIDsWithoutRows(serverID: UUID, among ids: [UInt]) async throws -> [UInt] {
    guard !ids.isEmpty else { return [] }
    return try await wrappingAsync("documentIDsWithoutRows") {
      try await writer.read { db in
        let cached = try Set(
          DocumentRecord
            .select(Column("id"), as: UInt.self)
            .filter(Column("server_id") == serverID && ids.contains(Column("id")))
            .fetchAll(db))
        var seen: Set<UInt> = []
        return ids.filter { seen.insert($0).inserted && !cached.contains($0) }
      }
    }
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
    try setQueryMeta(
      db, serverID: serverID, queryKey: queryKey,
      totalCount: try fetchQueryMeta(db, queryKey: queryKey, serverID: serverID)?.totalCount,
      basis: nil, stamp: .completed)
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

  /// Record that a list was put on screen at `date`.
  ///
  /// Creates the `query_meta` row if there isn't one yet: a list opened before
  /// its first page lands (offline, or with page 1 still in flight) was viewed
  /// all the same, and the fill that follows must not make it read as unseen.
  ///
  /// Written through ``QueryViewedRow`` rather than `QueryMetaRow`: each record's
  /// `upsert` sets only its own columns, so page writes and this stamp can't
  /// overwrite each other.
  public func markQueryViewed(
    queryKey: QueryKey, serverID: UUID, at date: Date = Date()
  ) async throws {
    try await wrappingAsync("markQueryViewed") {
      try await writer.write { db in
        try QueryViewedRow(serverId: serverID, queryKey: queryKey.rawValue, viewedAt: date)
          .upsert(db)
      }
    }
  }

  /// When this list was last put on screen, or `nil` if it never was (or its row
  /// predates the column).
  public func queryViewedAt(queryKey: QueryKey, serverID: UUID) async throws -> Date? {
    try await wrappingAsync("queryViewedAt") {
      try await writer.read { db in
        try QueryViewedRow
          .filter(Column("server_id") == serverID && Column("query_key") == queryKey.rawValue)
          .fetchOne(db)?.viewedAt
      }
    }
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
    let meta = try fetchQueryMeta(db, queryKey: queryKey, serverID: serverID)
    let order = try Row.fetchOne(
      db,
      sql: """
        SELECT COUNT(*) AS local_count, MAX(position) AS last_position FROM query_order
        WHERE server_id = ? AND query_key = ?
        """,
      arguments: [serverID, queryKey.rawValue])
    let localCount: Int = order?["local_count"] ?? 0
    let lastPosition: Int? = order?["last_position"]
    return QueryStatus(
      totalCount: meta?.totalCount, localCount: localCount,
      orderStale: meta?.orderStale ?? false,
      isComplete: isOrderComplete(
        filledAt: meta?.filledAt, lastPosition: lastPosition, totalCount: meta?.totalCount),
      orderGeneration: QueryOrderGeneration(meta?.orderGeneration ?? 0))
  }

  /// Whether a cached order is its query's whole membership.
  ///
  /// The fill stamp alone isn't enough: `truncateQuery` cuts the tail and keeps
  /// `filled_at` on purpose (the reachability LRU ranks on it, so a capped list
  /// has to keep its place). A cut order therefore also has to reach the
  /// server's total.
  ///
  /// Measured by the last position rather than the row count. A complete fill
  /// can hold fewer rows than the total — a document repeated across a page
  /// boundary is skipped by the `remote_id` unique key, and a remote delete
  /// prunes a row — but positions still run to the end, while a truncation
  /// always removes the tail. The one miss is conservative: a deleted *last*
  /// row reads as incomplete until the next fill.
  ///
  /// No recorded total leaves the stamp to decide.
  static func isOrderComplete(filledAt: Date?, lastPosition: Int?, totalCount: UInt?) -> Bool {
    guard filledAt != nil else { return false }
    let extent = lastPosition.map { $0 + 1 } ?? 0
    return extent >= Int(totalCount ?? 0)
  }

  static func fetchQueryMeta(
    _ db: GRDB.Database, queryKey: QueryKey, serverID: UUID
  ) throws -> QueryMetaRow? {
    try QueryMetaRow
      .filter(Column("server_id") == serverID && Column("query_key") == queryKey.rawValue)
      .fetchOne(db)
  }

  /// Upsert one document row (a straight replace: every write is the complete
  /// object), and mark stale every cached list that placed the document under a
  /// different `modified`. Returns how many lists were newly marked.
  ///
  /// Every document write goes through here, so a list is marked whichever path
  /// brings the new copy in first. An unknown placement adopts the new date.
  @discardableResult
  private static func writeDocumentRow(
    _ db: GRDB.Database, _ domain: Document, serverID: UUID
  ) throws -> Int {
    try DocumentRecord(serverId: serverID, domain: domain).upsert(db)
    guard let modified = domain.modified?.timeIntervalSinceReferenceDate else { return 0 }
    let placements = QueryOrderRow.filter(
      Column("server_id") == serverID && Column("remote_id") == domain.id)
    let moved = placements.filter(
      Column("placed_modified") != nil && Column("placed_modified") != modified)
    let marked = try markOrderStale(
      db, keys: moved.select(Column("query_key"), as: String.self), serverID: serverID)
    try placements
      .filter(Column("placed_modified") == nil || Column("placed_modified") != modified)
      .updateAll(db, Column("placed_modified").set(to: modified))
    return marked
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
  /// The stamp means *"the fill that owns this key paged it to the end"*, so a
  /// fill interrupted on page 2 doesn't read as complete.
  enum FillStamp {
    /// Page 1 of a fill has just deleted the key's whole order, so it is
    /// known-incomplete until the fill says otherwise.
    case cleared
    /// A later page, or a membership rewrite — leave whatever is recorded.
    case unchanged
    /// The fill's paging loop reached the end of the query.
    case completed
  }

  /// `basis` is the generation a whole-order rewrite accounts for; `nil` keeps
  /// the stored one.
  private static func setQueryMeta(
    _ db: GRDB.Database, serverID: UUID, queryKey: QueryKey,
    totalCount: UInt?, basis: QueryOrderGeneration?, stamp: FillStamp
  ) throws {
    // A record `upsert` rewrites every column, so whatever this write doesn't
    // set is carried forward, in the caller's transaction.
    let existing = try fetchQueryMeta(db, queryKey: queryKey, serverID: serverID)
    let filledAt: Date?
    switch stamp {
    case .cleared: filledAt = nil
    case .completed: filledAt = Date()
    case .unchanged: filledAt = existing?.filledAt
    }
    try QueryMetaRow(
      serverId: serverID, queryKey: queryKey.rawValue,
      totalCount: totalCount, filledAt: filledAt,
      orderGeneration: existing?.orderGeneration ?? 0,
      orderBasis: basis?.value ?? existing?.orderBasis ?? 0
    ).upsert(db)
  }
}
