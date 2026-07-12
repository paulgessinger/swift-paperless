import Foundation
import GRDB

/// Per-server sync-cursor operations (`server_sync_state`). The delta
/// watermark, the proactive-fill coverage timestamp, and the last-successful-
/// sync stamp are regenerable state, written by `CachingRepository` and reset
/// by `clearCache`. Dates cross the boundary as `Date?`; the on-disk shape
/// (REAL `timeIntervalSinceReferenceDate`) stays inside `Persistence`.
extension Database {
  /// The newest document `modified` the changed-metadata delta has applied for
  /// this server, or `nil` if it has never baselined.
  public func deltaWatermark(serverID: UUID) throws(DatabaseError) -> Date? {
    try wrapping("deltaWatermark") {
      try date(\.deltaWatermark, serverID: serverID)
    }
  }

  public func setDeltaWatermark(_ date: Date?, serverID: UUID) throws(DatabaseError) {
    try wrapping("setDeltaWatermark") {
      try update(serverID: serverID) { $0.deltaWatermark = date?.timeIntervalSinceReferenceDate }
    }
  }

  /// When this server's library was last fully filled, or `nil` if never.
  public func libraryCoverageAt(serverID: UUID) throws(DatabaseError) -> Date? {
    try wrapping("libraryCoverageAt") {
      try date(\.libraryCoverageAt, serverID: serverID)
    }
  }

  public func setLibraryCoverageAt(_ date: Date?, serverID: UUID) throws(DatabaseError) {
    try wrapping("setLibraryCoverageAt") {
      try update(serverID: serverID) { $0.libraryCoverageAt = date?.timeIntervalSinceReferenceDate }
    }
  }

  /// When this server's element sync last completed successfully, or `nil` if
  /// never. The persisted "fresh as of" stamp: stalest-first background sweep
  /// ordering and the Offline & Sync screen both read it.
  public func lastSyncAt(serverID: UUID) throws -> Date? {
    try date(\.lastSyncAt, serverID: serverID)
  }

  public func setLastSyncAt(_ date: Date?, serverID: UUID) throws {
    try update(serverID: serverID) { $0.lastSyncAt = date?.timeIntervalSinceReferenceDate }
  }

  /// All servers' `last_sync_at` stamps in one read, for sweep ordering.
  /// Servers with no row (or a `nil` stamp) are simply absent.
  public func lastSyncAts() throws -> [UUID: Date] {
    try writer.read { db in
      let records = try ServerSyncStateRecord.fetchAll(db)
      return Dictionary(
        uniqueKeysWithValues: records.compactMap { record in
          record.lastSyncAt.map { (record.serverId, Date(timeIntervalSinceReferenceDate: $0)) }
        })
    }
  }

  /// Observe this server's `last_sync_at`; same contract as
  /// ``observeLibraryCoverageAt(serverID:)``.
  public func observeLastSyncAt(serverID: UUID) -> AsyncThrowingStream<Date?, Error> {
    observeStamp(serverID: serverID, \.lastSyncAt)
  }

  /// Observe this server's `library_coverage_at`, emitting the current value
  /// immediately and again on every write (including a `clearCache` reset to
  /// `nil`). Backed by GRDB `ValueObservation`; consumers don't see GRDB types.
  public func observeLibraryCoverageAt(serverID: UUID) -> AsyncThrowingStream<Date?, Error> {
    observeStamp(serverID: serverID, \.libraryCoverageAt)
  }

  // MARK: - Helpers

  private func observeStamp(
    serverID: UUID, _ keyPath: KeyPath<ServerSyncStateRecord, Double?> & Sendable
  ) -> AsyncThrowingStream<Date?, Error> {
    let observation = ValueObservation.tracking { db in
      try ServerSyncStateRecord.fetchOne(db, key: serverID)?[keyPath: keyPath]
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

  private func date(
    _ keyPath: KeyPath<ServerSyncStateRecord, Double?>, serverID: UUID
  ) throws -> Date? {
    try writer.read { db in
      guard let stamp = try ServerSyncStateRecord.fetchOne(db, key: serverID)?[keyPath: keyPath]
      else { return nil }
      return Date(timeIntervalSinceReferenceDate: stamp)
    }
  }

  /// Read-modify-write upsert preserving the row's other columns.
  private func update(
    serverID: UUID, _ mutate: (inout ServerSyncStateRecord) -> Void
  ) throws {
    try writer.write { db in
      try Self.updateSyncState(db, serverID: serverID, mutate)
    }
  }

  /// Same read-modify-write, for callers that already hold a transaction and
  /// need the change to commit atomically with the rest of their work.
  static func updateSyncState(
    _ db: GRDB.Database, serverID: UUID, _ mutate: (inout ServerSyncStateRecord) -> Void
  ) throws {
    var record =
      try ServerSyncStateRecord.fetchOne(db, key: serverID)
      ?? ServerSyncStateRecord(serverId: serverID)
    mutate(&record)
    try record.upsert(db)
  }
}
