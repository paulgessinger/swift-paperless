import Foundation
import GRDB

/// What one *Recently browsed* cap pass did.
public struct RecentlyBrowsedCapResult: Sendable, Equatable {
  /// `query_order` rows cut off the tail of capped lists.
  public var truncatedRows: Int

  public init(truncatedRows: Int = 0) {
    self.truncatedRows = truncatedRows
  }
}

/// The *Recently browsed* storage cap, applied to lists nobody has looked at in
/// a while.
///
/// `reclaimAfterDowngrade` shrinks the cache once, at the *Entire library* →
/// *Recently browsed* transition. Nothing kept it there: every opened list
/// eager-fills in full (`fillQuery` is deliberately uncapped — scrolling is
/// local-only, so a cap there would dead-end the list even online), so the
/// cache grew straight back. This re-applies the same truncation to the lists
/// that haven't been viewed recently.
///
/// It cuts list membership only. Document rows stay whatever the lists say:
/// every document's metadata is kept in both modes, and only the remote-delete
/// sweep removes a row.
///
/// Async only, like every cache table — see the rule in `Database+Connections`.
extension Database {
  /// Cut every cached list for `serverID` not viewed since `cutoff` back to its
  /// first `keepingFirst` rows, in one transaction. Does nothing unless the
  /// server is in *Recently browsed*.
  ///
  /// **Run this only while nothing is showing or filling the server's lists.** A
  /// list cut while on screen dead-ends at the cap, because scrolling only widens
  /// a prefix over local rows, and a fill part-way through would go on appending
  /// pages behind the cut. The app runs it when a server's session first builds
  /// its repository, before any of its lists can open.
  ///
  /// - **Recency picks the lists, position picks the rows.** Within a list the cap
  ///   keeps a prefix in server order: the list view observes a growing prefix,
  ///   so keeping rows 700–900 instead of 200–700 would read offline as one list
  ///   that silently skips 500 documents. `viewed_at` is per list, so it decides
  ///   *whether* a list is cut.
  /// - A list with no stamp is eligible. That includes every list cached before
  ///   the column existed; the cost of guessing wrong is a refill on next open.
  /// - `exempting` is for lists about to be refilled in full anyway, where a cut
  ///   only buys a download.
  /// - The mode is read here rather than trusted from the caller.
  /// - `total_count`, `filled_at` and `viewed_at` survive, as in `truncateQuery`,
  ///   so the count pill keeps the server's total.
  @discardableResult
  public func capRecentlyBrowsedQueries(
    serverID: UUID,
    keepingFirst limit: Int,
    notViewedSince cutoff: Date,
    exempting exempt: Set<QueryKey> = []
  ) async throws -> RecentlyBrowsedCapResult {
    try await wrappingAsync("capRecentlyBrowsedQueries") {
      try await writer.write { db in
        // Raw value of AppShared's `OfflineBrowsingMode.recentlyBrowsed`, the
        // same literal `V1` defaults the column to. A missing server row means
        // there is nothing to cap (and its cache has cascaded away).
        let mode =
          try ConnectionRecord
          .select(ConnectionRecord.Columns.offlineBrowsingMode, as: String.self)
          .filter(ConnectionRecord.Columns.id == serverID)
          .fetchOne(db)
        guard mode == "recentlyBrowsed" else { return RecentlyBrowsedCapResult() }

        let scope = Column("server_id") == serverID
        let listed =
          try QueryOrderRow
          .filter(scope)
          .select(Column("query_key"), as: String.self)
          .distinct()
          .fetchSet(db)
        var viewedAt: [String: Date] = [:]
        for row in try QueryViewedRow.filter(scope).fetchAll(db) {
          viewedAt[row.queryKey] = row.viewedAt
        }
        let exemptKeys = Set(exempt.map(\.rawValue))

        var result = RecentlyBrowsedCapResult()
        for key in listed where !exemptKeys.contains(key) {
          if let viewed = viewedAt[key], viewed >= cutoff { continue }
          result.truncatedRows += try Self.truncateQuery(
            db, serverID: serverID, queryKey: QueryKey(stored: key), keepingFirst: limit)
        }
        return result
      }
    }
  }
}
