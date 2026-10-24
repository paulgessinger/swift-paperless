import Foundation
import GRDB

/// The *Kept offline* membership: which documents the user keeps on the
/// device. Every protection (document prune, file eviction, the downgrade's
/// archive removal) and the file pass ask this table, nothing else. Async
/// only, like every table but `server`.
extension Database {
  /// Keep or release one document. Keeping again refreshes `kept_at`, which
  /// moves the document to the top of the list.
  public func setKeptOffline(
    serverID: UUID, documentID: UInt, kept: Bool, at date: Date = Date()
  ) async throws {
    try await wrappingAsync("setKeptOffline") {
      try await writer.write { db in
        if kept {
          try KeptOfflineRecord(
            serverId: serverID, documentId: documentID,
            keptAt: date.timeIntervalSinceReferenceDate
          ).save(db)
        } else {
          _ =
            try KeptOfflineRecord
            .filter(Column("server_id") == serverID && Column("document_id") == documentID)
            .deleteAll(db)
        }
      }
    }
  }

  /// The kept documents of a server.
  public func keptOfflineIDs(serverID: UUID) async throws -> Set<UInt> {
    try await wrappingAsync("keptOfflineIDs") {
      try await writer.read { db in try Self.keptOfflineIDs(db, serverID: serverID) }
    }
  }

  /// Whether one document is kept.
  public func isKeptOffline(serverID: UUID, documentID: UInt) async throws -> Bool {
    try await wrappingAsync("isKeptOffline") {
      try await writer.read { db in
        try
          !KeptOfflineRecord
          .filter(Column("server_id") == serverID && Column("document_id") == documentID)
          .isEmpty(db)
      }
    }
  }

  /// Live ``keptOfflineIDs(serverID:)``, for the list's badges and the
  /// detail view's toggle.
  public func observeKeptOfflineIDs(serverID: UUID) -> AsyncThrowingStream<Set<UInt>, Error> {
    let observation =
      ValueObservation
      .tracking { db in try Self.keptOfflineIDs(db, serverID: serverID) }
      .removeDuplicates()
    return stream(observation)
  }

  /// Kept documents with no cached `document` row: what the reconcile fetches
  /// so the list has rows and the file pass has a `modified` to download
  /// against. After a cache wipe this is every kept document.
  public func keptOfflineIDsMissingRows(serverID: UUID) async throws -> [UInt] {
    try await wrappingAsync("keptOfflineIDsMissingRows") {
      try await writer.read { db in
        try UInt.fetchAll(
          db,
          sql: """
            SELECT k.document_id FROM kept_offline k
            LEFT JOIN document d ON d.server_id = k.server_id AND d.id = k.document_id
            WHERE k.server_id = ? AND d.id IS NULL
            ORDER BY k.kept_at DESC
            """,
          arguments: [serverID])
      }
    }
  }

  // MARK: - Query bodies

  static func keptOfflineIDs(_ db: GRDB.Database, serverID: UUID) throws -> Set<UInt> {
    try KeptOfflineRecord
      .filter(Column("server_id") == serverID)
      .select(Column("document_id"), as: UInt.self)
      .fetchSet(db)
  }

  /// `d` is kept, on its own or by a kept saved view that lists it,
  /// correlated on a `document d` in raw SQL. The SQL twin of
  /// ``KeptOfflineRecord/isKept(server:document:)``.
  static let keptOfflineExists = """
    (EXISTS (
      SELECT 1 FROM kept_offline k
      WHERE k.server_id = d.server_id AND k.document_id = d.id
    ) OR EXISTS (
      SELECT 1 FROM kept_offline_view v
      JOIN query_order q ON q.server_id = v.server_id AND q.query_key = v.query_key
      WHERE v.server_id = d.server_id AND q.remote_id = d.id
    ))
    """

  /// The *Kept offline* list: newest membership first, a skeleton for a kept
  /// document whose row is not cached yet. Served under ``QueryKey/keptOffline``
  /// in place of the `query_order` replay.
  static let keptOfflineWindowSQL = """
    SELECT k.document_id AS remote_id, d.* FROM kept_offline k
    LEFT JOIN document d ON d.server_id = k.server_id AND d.id = k.document_id
    WHERE k.server_id = ?
    ORDER BY k.kept_at DESC, k.document_id DESC
    LIMIT ? OFFSET ?
    """

  /// The list's status: the membership is always complete and never stale,
  /// and `localCount` says how many members have a row.
  static func fetchKeptOfflineStatus(_ db: GRDB.Database, serverID: UUID) throws -> QueryStatus {
    let row = try Row.fetchOne(
      db,
      sql: """
        SELECT COUNT(*) AS total, COUNT(d.id) AS local_count FROM kept_offline k
        LEFT JOIN document d ON d.server_id = k.server_id AND d.id = k.document_id
        WHERE k.server_id = ?
        """,
      arguments: [serverID])
    let total: Int = row?["total"] ?? 0
    return QueryStatus(
      totalCount: UInt(total), localCount: row?["local_count"] ?? 0,
      orderStale: false, isComplete: true, orderGeneration: QueryOrderGeneration(0))
  }
}
