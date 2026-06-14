import Foundation
import GRDB

/// A proactive-sync failure for one cached query, surfaced to the UI so the user
/// learns a saved view (or the default list) couldn't be filled for offline use.
/// `savedViewName` is `nil` for the default list. Crosses the package boundary
/// as a value type — consumers never see GRDB or on-disk REAL timestamps.
public struct QuerySyncError: Sendable, Equatable, Identifiable {
  public let queryKey: String
  public let savedViewName: String?
  public let message: String
  public let failedAt: Date

  public var id: String { queryKey }

  public init(queryKey: String, savedViewName: String?, message: String, failedAt: Date) {
    self.queryKey = queryKey
    self.savedViewName = savedViewName
    self.message = message
    self.failedAt = failedAt
  }
}

/// Per-query sync-failure tracking (`query_sync_error`). The proactive fill and
/// membership sweep record a row when a view is rejected and delete it on the
/// next success; the Offline & Sync screen observes the active server's set.
extension Database {
  /// Record (upsert) the latest sync failure for a query.
  public func recordQuerySyncError(
    serverID: UUID, queryKey: String, savedViewName: String?, message: String,
    at date: Date = Date()
  ) throws {
    try writer.write { db in
      try QuerySyncErrorRecord(
        serverId: serverID, queryKey: queryKey, savedViewName: savedViewName,
        message: message, failedAt: date.timeIntervalSinceReferenceDate
      ).upsert(db)
    }
  }

  /// Clear a query's recorded failure (called when it next syncs successfully).
  public func clearQuerySyncError(serverID: UUID, queryKey: String) throws {
    _ = try writer.write { db in
      try QuerySyncErrorRecord
        .filter(Column("server_id") == serverID && Column("query_key") == queryKey)
        .deleteAll(db)
    }
  }

  /// Observe this server's recorded sync failures (newest first), emitting the
  /// current set immediately and again on every change.
  public func observeQuerySyncErrors(serverID: UUID)
    -> AsyncThrowingStream<[QuerySyncError], Error>
  {
    let observation = ValueObservation.tracking { db in
      try QuerySyncErrorRecord
        .filter(Column("server_id") == serverID)
        .order(Column("failed_at").desc)
        .fetchAll(db)
    }
    let writer = writer
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await records in observation.values(in: writer) {
            continuation.yield(
              records.map {
                QuerySyncError(
                  queryKey: $0.queryKey, savedViewName: $0.savedViewName,
                  message: $0.message,
                  failedAt: Date(timeIntervalSinceReferenceDate: $0.failedAt))
              })
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
