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
  /// Unions all three query tables rather than reading `query_meta` alone: a key
  /// with membership rows but no meta row, or with nothing but a recorded sync
  /// failure (a first fill that failed before it wrote anything else), should not
  /// be invisible to a GC whose whole job is finding rows nothing points at. An
  /// error-only orphan that the sweep cannot see is a broken saved view rendered
  /// on the Offline & Sync screen with nothing left that could ever clear it.
  public func cachedQueries(serverID: UUID) async throws -> [CachedQuery] {
    try await wrappingAsync("cachedQueries") {
      try await writer.read { db in
        var filledAt: [String: Date?] = [:]
        for row in try QueryMetaRow.filter(Column("server_id") == serverID).fetchAll(db) {
          filledAt[row.queryKey] = row.filledAt
        }
        let unstamped = try String.fetchAll(
          db,
          sql: """
            SELECT DISTINCT query_key FROM query_order WHERE server_id = ?
            UNION SELECT query_key FROM query_sync_error WHERE server_id = ?
            """,
          arguments: [serverID, serverID])
        for key in unstamped where filledAt.index(forKey: key) == nil {
          filledAt[key] = Date?.none
        }
        return filledAt.map { CachedQuery(key: QueryKey(stored: $0.key), filledAt: $0.value) }
      }
    }
  }

  /// Delete `query_order` / `query_meta` / `query_sync_error` for every key in
  /// `collectedKeys`, in one transaction. Returns the number of *keys* that
  /// actually had rows.
  ///
  /// One transaction because the three tables hold one fact split three ways: a
  /// key whose membership is gone but whose recorded sync error survives would
  /// go on being rendered as a broken saved view on the Offline & Sync screen,
  /// with nothing left that could ever clear it.
  ///
  /// The predicate is the explicit collected set rather than `NOT IN (reachable)`
  /// precisely because the two are *not* equivalent for keys the caller never
  /// saw. `NOT IN (reachable)` also matches every key created after the caller
  /// took its snapshot, so a fill for a never-before-cached key could land its
  /// page-one rows inside this delete's window and lose them — and then go on
  /// appending page two at a nonzero position, leaving that list truncated in
  /// the cache until something refilled it. Naming the keys makes the sweep
  /// incapable of collecting a query it never observed; anything unreachable
  /// that appeared since is simply collected by the next pass.
  ///
  /// The set is unbounded — it is the very thing this GC exists because of — so
  /// it is deleted in chunks to stay under SQLite's bound-parameter limit. The
  /// chunks share the one transaction; a partial prune is not a state any reader
  /// should see.
  @discardableResult
  public func pruneQueries(
    serverID: UUID, collectedKeys: Set<QueryKey>
  ) async throws -> Int {
    try await wrappingAsync("pruneQueries") {
      guard !collectedKeys.isEmpty else { return 0 }
      return try await writer.write { db in
        let scope = Column("server_id") == serverID
        let all = collectedKeys.map(\.rawValue)
        var collected = 0
        for start in stride(from: 0, to: all.count, by: Self.pruneKeyChunk) {
          let chunk = Array(all[start..<min(start + Self.pruneKeyChunk, all.count)])
          let inChunk = chunk.contains(Column("query_key"))
          var present = try QueryMetaRow.filter(scope && inChunk)
            .select(Column("query_key"), as: String.self).fetchSet(db)
          try present.formUnion(
            QueryOrderRow.filter(scope && inChunk)
              .select(Column("query_key"), as: String.self).fetchSet(db))
          try present.formUnion(
            QuerySyncErrorRecord.filter(scope && inChunk)
              .select(Column("query_key"), as: String.self).fetchSet(db))
          collected += present.count

          try QueryOrderRow.filter(scope && inChunk).deleteAll(db)
          try QueryMetaRow.filter(scope && inChunk).deleteAll(db)
          try QuerySyncErrorRecord.filter(scope && inChunk).deleteAll(db)
        }
        return collected
      }
    }
  }

  /// Keys per `IN (...)`. SQLite's default `SQLITE_MAX_VARIABLE_NUMBER` is far
  /// higher, but three statements share each chunk and the bound is not worth
  /// depending on.
  private static var pruneKeyChunk: Int { 500 }
}
