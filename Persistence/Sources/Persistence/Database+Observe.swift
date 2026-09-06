import DataModel
import Foundation
import GRDB

/// Typed live queries over the element cache — the source-of-truth read path.
///
/// Like ``Database/observeConnections()``, each method wraps GRDB
/// `ValueObservation` and surfaces it as an `AsyncThrowingStream` of **domain**
/// values: GRDB, `ValueObservation`, and SQL never cross the `Persistence`
/// boundary. The first element is the current state (so a consumer's
/// `for try await` loop is "initial hydrate + live updates" in one), exactly
/// like the connection observer.
///
/// Each emission carries the freshly-mapped domain result, so a consumer
/// assigns it directly and never re-reads the database to find out what
/// changed.
///
/// ## Scope: why these streams stay quiet for other servers
///
/// A GRDB observation tracks a *database region*, and a region is only
/// `(table, columns, rowIDs)`. The rowID set is narrowed solely when the
/// request filters on the rowid itself (`SQLQueryGenerator.optimizedSelectedRegion`
/// → `SQLExpression.identifyingRowIDs`), and none of these tables is keyed by
/// rowid — they are keyed `(server_id, …)`. A `server_id` predicate is
/// therefore *not expressible* as a region, and there is no region narrowing to
/// be had: a write for another server still wakes every observation on that
/// table and re-runs its fetch. That matters now that the inactive-server
/// sweep keeps every configured server's cache warm, not just the active one.
///
/// What such a write no longer does is reach the consumer. Every observation
/// below fetches **records**, applies `removeDuplicates()`, and only then maps
/// to domain values, so for a server whose rows did not change the fetched
/// records compare equal, the stream stays silent, and neither the
/// record → domain mapping nor the consumer's re-publish (main-actor hop,
/// SwiftUI invalidation, store re-derivation) runs. The residual cost of a
/// foreign write is one SQL fetch per live observation — the floor GRDB's
/// region granularity allows.
///
/// `removeDuplicates()` never suppresses the initial value: the first emission
/// is always delivered, so the "initial hydrate + live updates" contract holds.
extension Database {
  /// Live, name-ordered list of one element collection for a server.
  ///
  /// `R` is `Equatable` so the fetched rows can be de-duplicated *before* the
  /// domain mapping — see the type-level note on scope.
  public func observeElements<R: ElementRecord & Equatable>(
    _ type: R.Type, serverID: UUID
  ) -> AsyncThrowingStream<[R.Domain], Error> {
    let observation =
      ValueObservation
      .tracking { db in
        try R
          .filter(Column("server_id") == serverID)
          .order(Column("name"))
          .fetchAll(db)
      }
      .removeDuplicates()
      .map { records in records.map(\.domain) }
    return stream(observation)
  }

  /// Live per-server `UISettings` singleton (`nil` until first cached/synced).
  public func observeUISettings(serverID: UUID) -> AsyncThrowingStream<UISettings?, Error> {
    let observation =
      ValueObservation
      .tracking { db in
        try UISettingsRecord.fetchOne(db, key: serverID)
      }
      .removeDuplicates()
      .map { record in record?.domain }
    return stream(observation)
  }

  /// Live per-server `ServerConfiguration` singleton (`nil` until cached/synced).
  public func observeServerConfiguration(
    serverID: UUID
  ) -> AsyncThrowingStream<ServerConfiguration?, Error> {
    let observation =
      ValueObservation
      .tracking { db in
        try ServerConfigurationRecord.fetchOne(db, key: serverID)
      }
      .removeDuplicates()
      .map { record in record?.domain }
    return stream(observation)
  }

  /// Live **growing prefix** of a cached query's ordered answer: the
  /// `query_order ⋈ document` join, `ORDER BY position LIMIT <limit>` (offset is
  /// always 0 — this is a prefix, not a sliding window, so scroll-back needs no
  /// re-subscription and deletion gaps in `position` are invisible).
  ///
  /// The list view-model grows `limit` monotonically as the user scrolls and
  /// re-subscribes; per-emission work is bounded by `limit` (what's been scrolled
  /// to), not the whole filled set — the win over observing the entire array
  /// during the eager background fill. Re-fires automatically as the fill appends
  /// rows and as mutations write the joined `document` rows.
  ///
  /// The join re-runs for any write to `query_order`/`document`, another
  /// server's included (see the type-level scope note); de-duplication is what
  /// keeps an unchanged prefix from reaching the list.
  public func observeDocumentPrefix(
    queryKey: QueryKey, serverID: UUID, limit: Int
  ) -> AsyncThrowingStream<[DocumentEntry], Error> {
    let key = queryKey.rawValue
    let observation =
      ValueObservation
      .tracking { db -> [DocumentEntry] in
        try Self.fetchEntries(db, serverID: serverID, queryKey: key, limit: limit, offset: 0)
      }
      .removeDuplicates()
    return stream(observation)
  }

  /// Live status of a cached query — server total, locally-present count
  /// (reflects deletion gaps), order-stale flag. Tracks
  /// both `query_meta` and `query_order`, so a fill, a delete, or a stale-marking
  /// re-fires it.
  public func observeQueryStatus(
    queryKey: QueryKey, serverID: UUID
  ) -> AsyncThrowingStream<QueryStatus, Error> {
    let observation =
      ValueObservation
      .tracking { db -> QueryStatus in
        try Self.fetchQueryStatus(db, queryKey: queryKey, serverID: serverID)
      }
      .removeDuplicates()
    return stream(observation)
  }

  /// Live single document by `(server, id)` (`nil` until cached) — the
  /// single-row analogue of ``observeDocumentPrefix``, for surfaces that display
  /// one document and must repaint on mutation/sync (detail, preview).
  public func observeDocument(
    serverID: UUID, id: UInt
  ) -> AsyncThrowingStream<Document?, Error> {
    let observation =
      ValueObservation
      .tracking { db -> DocumentRecord? in
        try DocumentRecord
          .filter(Column("server_id") == serverID && Column("id") == id)
          .fetchOne(db)
      }
      .removeDuplicates()
      .map { record in record?.domain }
    return stream(observation)
  }

  /// Live count of `document` rows cached for a server — a diagnostic surface
  /// (the Offline & Sync screen) so the proactive fill and the downgrade GC's
  /// effect are visible without a debugger.
  public func observeDocumentCount(serverID: UUID) -> AsyncThrowingStream<Int, Error> {
    let observation =
      ValueObservation
      .tracking { db in
        try DocumentRecord.filter(Column("server_id") == serverID).fetchCount(db)
      }
      .removeDuplicates()
    return stream(observation)
  }

  /// Shared adapter: drive a `ValueObservation` into an `AsyncThrowingStream`,
  /// mirroring ``observeConnections()``. Cancelling the consuming task tears
  /// down the underlying observation.
  ///
  /// Generic over the reducer rather than over `ValueReducers.Fetch` so the
  /// `removeDuplicates()`/`map` chains above — each of which wraps the reducer
  /// in another one — all go through this same adapter.
  private func stream<Reducer: ValueReducer>(
    _ observation: ValueObservation<Reducer>
  ) -> AsyncThrowingStream<Reducer.Value, Error> {
    let writer = writer
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await value in observation.values(in: writer) {
            continuation.yield(value)
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
