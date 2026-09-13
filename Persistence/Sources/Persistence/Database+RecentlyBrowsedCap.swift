import Foundation
import GRDB

/// What one *Recently browsed* cap pass did.
public struct RecentlyBrowsedCapResult: Sendable, Equatable {
  /// `query_order` rows cut off the tail of capped lists.
  public var truncatedRows: Int
  /// Documents no cached list referenced any more once the tails were gone.
  public var removedDocuments: Int

  public init(truncatedRows: Int = 0, removedDocuments: Int = 0) {
    self.truncatedRows = truncatedRows
    self.removedDocuments = removedDocuments
  }
}

extension QueryRetention {
  /// Which cached lists the recurring *Recently browsed* cap may shorten: every
  /// key that is neither `pinned` (in use right now) nor completed at or after
  /// `completedBefore`.
  ///
  /// **Recency picks the lists, position picks the rows.** Within one list the
  /// cap always keeps a prefix in server order: the list view observes a
  /// growing prefix by ordered row offset, so keeping, say, rows 700–900 instead
  /// of 200–700 would read offline as one contiguous list that silently jumps
  /// 500 documents. There is also no per-row recency to key on — `query_order`
  /// carries none, and `filled_at` is per list. Recency therefore decides
  /// *whether* a list is capped: one a fill paged to the end recently is
  /// something the user just browsed, and keeping it whole is what stops the
  /// next sweep evicting the older documents they scrolled down to.
  ///
  /// A key with no stamp is eligible. The stamp is cleared by every page-one
  /// write and only set when a fill reaches the end, so its absence is a list no
  /// fill is completing; in-flight fills are the caller's to pin, as for
  /// ``mostRecentlyFilled(_:limit:)``.
  public static func recentlyBrowsedCapCandidates(
    _ cached: [CachedQuery], pinned: Set<QueryKey>, completedBefore cutoff: Date
  ) -> Set<QueryKey> {
    Set(
      cached
        .filter { !pinned.contains($0.key) }
        .filter { candidate in
          guard let filledAt = candidate.filledAt else { return true }
          return filledAt < cutoff
        }
        .map(\.key))
  }
}

/// The recurring half of the *Recently browsed* storage cap.
///
/// `reclaimAfterDowngrade` shrinks the cache once, at the *Entire library* →
/// *Recently browsed* transition. Nothing kept it there: every opened list
/// eager-fills in full (`fillQuery` is deliberately uncapped — scrolling is
/// local-only, so a cap there would dead-end the list even online), so the
/// cache grew straight back. This re-applies the same truncate-then-prune on
/// an ongoing basis, to lists nobody is using, so storage settles back down
/// after a browsing session.
///
/// Async only, like every cache table — see the rule in `Database+Connections`.
extension Database {
  /// Cap each of `candidateKeys` to its first `keepingFirst` rows and prune the
  /// documents that frees, in one transaction — but only while the server is
  /// in *Recently browsed*, and never for a list completed at or after
  /// `completedBefore`.
  ///
  /// - The mode is read inside the transaction rather than trusted from the
  ///   caller, so an upgrade to *Entire library* that commits first is honoured
  ///   instead of having its freshly filled lists cut back.
  /// - The stamp is re-checked inside the transaction for the same reason: the
  ///   caller's candidate set is a snapshot, and a list completed since is a
  ///   list the user just browsed.
  /// - Only the named keys are touched, never "everything else". A fill for a
  ///   key the caller didn't see may have appended pages already; truncating it
  ///   would leave that fill appending at positions past a hole, i.e. a cached
  ///   list silently missing documents. (Same argument as ``pruneQueries``.)
  /// - `total_count` and `filled_at` survive, as in `truncateQuery`: the count
  ///   pill keeps the server's total, and the reachability LRU keeps ranking the
  ///   list by when it was really browsed.
  /// - The document prune only runs when a tail was actually cut. In steady
  ///   state nothing exceeds the cap, and the anti-join would otherwise scan the
  ///   whole document table on every reconcile to find nothing.
  @discardableResult
  public func capRecentlyBrowsedQueries(
    serverID: UUID,
    candidateKeys: Set<QueryKey>,
    keepingFirst limit: Int,
    completedBefore cutoff: Date
  ) async throws -> RecentlyBrowsedCapResult {
    try await wrappingAsync("capRecentlyBrowsedQueries") {
      guard !candidateKeys.isEmpty else { return RecentlyBrowsedCapResult() }
      return try await writer.write { db in
        // Raw value of AppShared's `OfflineBrowsingMode.recentlyBrowsed`, the
        // same literal `V1` defaults the column to. A missing server row means
        // there is nothing to cap (and its cache has cascaded away).
        let mode = try String.fetchOne(
          db, sql: "SELECT offline_browsing_mode FROM server WHERE id = ?",
          arguments: [serverID])
        guard mode == "recentlyBrowsed" else { return RecentlyBrowsedCapResult() }

        var result = RecentlyBrowsedCapResult()
        for key in candidateKeys {
          let filledAt =
            try QueryMetaRow
            .filter(Column("server_id") == serverID && Column("query_key") == key.rawValue)
            .fetchOne(db)?.filledAt
          if let filledAt, filledAt >= cutoff { continue }
          result.truncatedRows += try Self.truncateQuery(
            db, serverID: serverID, queryKey: key, keepingFirst: limit)
        }
        if result.truncatedRows > 0 {
          result.removedDocuments = try Self.pruneUnreferenced(db, serverID: serverID)
        }
        return result
      }
    }
  }
}
