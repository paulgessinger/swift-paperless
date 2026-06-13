import Foundation
import GRDB

/// Per-server sync-cursor operations (`server_sync_state`). The delta watermark
/// and the proactive-fill coverage timestamp are regenerable state, written by
/// `CachingRepository` and reset by `clearCache`. Dates cross the boundary as
/// `Date?`; the on-disk shape (REAL `timeIntervalSinceReferenceDate`) stays
/// inside `Persistence`.
extension Database {
  /// The newest document `modified` the changed-metadata delta has applied for
  /// this server, or `nil` if it has never baselined.
  public func deltaWatermark(serverID: UUID) throws -> Date? {
    try date(\.deltaWatermark, serverID: serverID)
  }

  public func setDeltaWatermark(_ date: Date?, serverID: UUID) throws {
    try update(serverID: serverID) { $0.deltaWatermark = date?.timeIntervalSinceReferenceDate }
  }

  /// When this server's library was last fully filled, or `nil` if never.
  public func libraryCoverageAt(serverID: UUID) throws -> Date? {
    try date(\.libraryCoverageAt, serverID: serverID)
  }

  public func setLibraryCoverageAt(_ date: Date?, serverID: UUID) throws {
    try update(serverID: serverID) { $0.libraryCoverageAt = date?.timeIntervalSinceReferenceDate }
  }

  /// Observe this server's `library_coverage_at`, emitting the current value
  /// immediately and again on every write (including a `clearCache` reset to
  /// `nil`). Backed by GRDB `ValueObservation`; consumers don't see GRDB types.
  public func observeLibraryCoverageAt(serverID: UUID) -> AsyncThrowingStream<Date?, Error> {
    let observation = ValueObservation.tracking { db in
      try ServerSyncStateRecord.fetchOne(db, key: serverID)?.libraryCoverageAt
    }
    let writer = writer
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await stamp in observation.values(in: writer) {
            continuation.yield(stamp.map { Date(timeIntervalSinceReferenceDate: $0) })
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

  // MARK: - Helpers

  private func date(
    _ keyPath: KeyPath<ServerSyncStateRecord, Double?>, serverID: UUID
  ) throws -> Date? {
    try writer.read { db in
      guard let stamp = try ServerSyncStateRecord.fetchOne(db, key: serverID)?[keyPath: keyPath]
      else { return nil }
      return Date(timeIntervalSinceReferenceDate: stamp)
    }
  }

  /// Read-modify-write upsert preserving the row's other column.
  private func update(
    serverID: UUID, _ mutate: (inout ServerSyncStateRecord) -> Void
  ) throws {
    try writer.write { db in
      var record =
        try ServerSyncStateRecord.fetchOne(db, key: serverID)
        ?? ServerSyncStateRecord(serverId: serverID)
      mutate(&record)
      try record.upsert(db)
    }
  }
}
