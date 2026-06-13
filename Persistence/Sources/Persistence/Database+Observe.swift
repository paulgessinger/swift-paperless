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
/// These replace the cache-aside variant's coarse `CacheChange` signal +
/// `hydrate()`: the observation *carries the data* (the freshly-mapped domain
/// result), so the store/projection assigns it directly with no re-read.
///
/// Scope: in Stage 7 the active server is singular. The observation tracks the
/// whole table region, so a write to *another* server's rows re-fires this
/// stream with an identical array — harmless at one active server; not worth
/// narrowing.
extension Database {
  /// Live, name-ordered list of one element collection for a server.
  public func observeElements<R: ElementRecord>(
    _ type: R.Type, serverID: UUID
  ) -> AsyncThrowingStream<[R.Domain], Error> {
    let observation = ValueObservation.tracking { db in
      try R
        .filter(Column("server_id") == serverID)
        .order(Column("name"))
        .fetchAll(db)
        .map(\.domain)
    }
    return stream(observation)
  }

  /// Live per-server `UISettings` singleton (`nil` until first cached/synced).
  public func observeUISettings(serverID: UUID) -> AsyncThrowingStream<UISettings?, Error> {
    let observation = ValueObservation.tracking { db in
      try UISettingsRecord.fetchOne(db, key: serverID)?.domain
    }
    return stream(observation)
  }

  /// Live per-server `ServerConfiguration` singleton (`nil` until cached/synced).
  public func observeServerConfiguration(
    serverID: UUID
  ) -> AsyncThrowingStream<ServerConfiguration?, Error> {
    let observation = ValueObservation.tracking { db in
      try ServerConfigurationRecord.fetchOne(db, key: serverID)?.domain
    }
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
  public func observeDocumentPrefix(
    queryKey: QueryKey, serverID: UUID, limit: Int
  ) -> AsyncThrowingStream<[Document], Error> {
    let key = queryKey.rawValue
    let observation = ValueObservation.tracking { db -> [Document] in
      try DocumentRecord.fetchAll(
        db, sql: Self.queryWindowSQL,
        arguments: [serverID, key, limit, 0]
      ).map(\.domain)
    }
    return stream(observation)
  }

  /// Live status of a cached query — server total (scrollbar extent),
  /// locally-present count (reflects deletion gaps), order-stale flag. Tracks
  /// both `query_meta` and `query_order`, so a fill, a delete, or a stale-marking
  /// re-fires it.
  public func observeQueryStatus(
    queryKey: QueryKey, serverID: UUID
  ) -> AsyncThrowingStream<QueryStatus, Error> {
    let observation = ValueObservation.tracking { db -> QueryStatus in
      try Self.fetchQueryStatus(db, queryKey: queryKey, serverID: serverID)
    }
    return stream(observation)
  }

  /// Live single document by `(server, id)` (`nil` until cached) — the
  /// single-row analogue of ``observeDocumentPrefix``, for surfaces that display
  /// one document and must repaint on mutation/sync (detail, preview).
  public func observeDocument(
    serverID: UUID, id: UInt
  ) -> AsyncThrowingStream<Document?, Error> {
    let observation = ValueObservation.tracking { db -> Document? in
      try DocumentRecord
        .filter(Column("server_id") == serverID && Column("id") == id)
        .fetchOne(db)?
        .domain
    }
    return stream(observation)
  }

  /// Shared adapter: drive a `ValueObservation` into an `AsyncThrowingStream`,
  /// mirroring ``observeConnections()``. Cancelling the consuming task tears
  /// down the underlying observation.
  private func stream<Value: Sendable>(
    _ observation: ValueObservation<ValueReducers.Fetch<Value>>
  ) -> AsyncThrowingStream<Value, Error> {
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
