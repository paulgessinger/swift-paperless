import Foundation
import GRDB

/// One cached query as the reachability sweep sees it: its key and the last time
/// a fill paged it to the end (`nil` if none ever did — see
/// ``Database/FillStamp``).
public struct CachedQuery: Sendable, Equatable {
  public let key: QueryKey
  public let filledAt: Date?

  public init(key: QueryKey, filledAt: Date?) {
    self.key = key
    self.filledAt = filledAt
  }
}

/// The *mechanism* half of the query-key GC: which of a server's cached keys an
/// LRU would keep. The *policy* — how many, and which keys are reachable for
/// other reasons (the default list, the saved views, an in-flight fill) — lives
/// with the caching repository, which is the only thing that knows them.
///
/// Pure and host-testable on purpose: it is the one part of the sweep with a
/// non-obvious rule, and `AppShared` has no test target.
public enum QueryRetention {
  /// The `limit` most recently *completed* queries.
  ///
  /// A candidate with no `filledAt` is not eligible. The stamp means "a fill
  /// paged this key to the end", so its absence is either a fill that never
  /// finished or one that was re-baselined and abandoned — in both cases the
  /// rows are a partial answer nothing is going to complete, which is exactly
  /// the garbage this sweep exists to collect. Keys that are still *in use*
  /// (displayed, or mid-fill) are pinned by the caller, not by this stamp.
  ///
  /// Ties break on the key itself so the choice is deterministic — two queries
  /// filled inside the same clock tick must not make the sweep's outcome depend
  /// on dictionary order.
  public static func mostRecentlyFilled(
    _ candidates: [CachedQuery], limit: Int
  ) -> Set<QueryKey> {
    guard limit > 0 else { return [] }
    let ranked =
      candidates
      .compactMap { candidate -> (key: QueryKey, filledAt: Date)? in
        guard let filledAt = candidate.filledAt else { return nil }
        return (candidate.key, filledAt)
      }
      .sorted {
        $0.filledAt == $1.filledAt
          ? $0.key.rawValue < $1.key.rawValue
          : $0.filledAt > $1.filledAt
      }
    return Set(ranked.prefix(limit).map(\.key))
  }
}

/// Reachability GC for cached query keys.
///
/// A `QueryKey` is a hash of the *effective server query*, so a key stops being
/// produced the moment its inputs change — the user edits a filter or a sort, a
/// saved view is edited server-side, the default sort setting changes. Nothing
/// used to delete those rows, so every filter combination ever browsed stayed on
/// disk for the life of the install, and (because `pruneUnreferencedDocuments`
/// anti-joins against `query_order`) went on pinning its documents as well.
///
/// Async only, like every cache table — see the rule in `Database+Connections`.
extension Database {
  /// Every query key this server has rows for, with the last time it was filled
  /// to completion — the candidate set the reachability policy chooses from.
  ///
  /// Unions `query_order` in rather than reading `query_meta` alone: a key with
  /// membership rows but no meta row should not be invisible to a GC whose whole
  /// job is finding rows nothing points at.
  public func cachedQueries(serverID: UUID) async throws -> [CachedQuery] {
    try await wrappingAsync("cachedQueries") {
      try await writer.read { db in
        var filledAt: [String: Date?] = [:]
        for row in try QueryMetaRow.filter(Column("server_id") == serverID).fetchAll(db) {
          filledAt[row.queryKey] = row.filledAt
        }
        let orderKeys = try String.fetchAll(
          db, sql: "SELECT DISTINCT query_key FROM query_order WHERE server_id = ?",
          arguments: [serverID])
        for key in orderKeys where filledAt.index(forKey: key) == nil {
          filledAt[key] = Date?.none
        }
        return filledAt.map { CachedQuery(key: QueryKey(stored: $0.key), filledAt: $0.value) }
      }
    }
  }

  /// Delete `query_order` / `query_meta` / `query_sync_error` for every key of
  /// `serverID` outside `reachableKeys`, in one transaction. Returns the number
  /// of *keys* collected.
  ///
  /// One transaction because the three tables hold one fact split three ways: a
  /// key whose membership is gone but whose recorded sync error survives would
  /// go on being rendered as a broken saved view on the Offline & Sync screen,
  /// with nothing left that could ever clear it.
  ///
  /// The predicate is `NOT IN (reachable)` rather than `IN (collected)` — the
  /// reachable set is bounded by policy, while the collected set is exactly the
  /// unbounded thing this GC exists because of, and would eventually exceed
  /// SQLite's bound-parameter limit.
  ///
  /// An empty `reachableKeys` means nothing is reachable and drops the server's
  /// whole query cache. That is the honest reading; the caller never passes one
  /// by accident, since the default list is always reachable.
  @discardableResult
  public func pruneUnreachableQueries(
    serverID: UUID, reachableKeys: Set<QueryKey>
  ) async throws -> Int {
    try await wrappingAsync("pruneUnreachableQueries") {
      try await writer.write { db in
        let reachable = Set(reachableKeys.map(\.rawValue))
        let present = try String.fetchAll(
          db,
          sql: """
            SELECT query_key FROM query_meta WHERE server_id = ?
            UNION SELECT query_key FROM query_order WHERE server_id = ?
            UNION SELECT query_key FROM query_sync_error WHERE server_id = ?
            """,
          arguments: [serverID, serverID, serverID])
        let collected = present.filter { !reachable.contains($0) }
        guard !collected.isEmpty else { return 0 }

        let scope = Column("server_id") == serverID
        let unreachable = !Array(reachable).contains(Column("query_key"))
        try QueryOrderRow.filter(scope && unreachable).deleteAll(db)
        try QueryMetaRow.filter(scope && unreachable).deleteAll(db)
        try QuerySyncErrorRecord.filter(scope && unreachable).deleteAll(db)
        return collected.count
      }
    }
  }
}
