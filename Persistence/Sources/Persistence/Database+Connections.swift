import Foundation
import GRDB

/// Connection-table operations.
///
/// These are the only entry points `ConnectionManager` uses to read or
/// mutate `server` rows; GRDB stays hidden from AppShared and the rest of
/// the app. Stage 7 will add analogous APIs for element and document
/// records under the same principle ("GRDB is sealed inside Persistence").
extension Database {
  /// Fetch every connection row currently in the table.
  public func allConnections() throws -> [ConnectionRecord] {
    try writer.read { db in
      try ConnectionRecord.fetchAll(db)
    }
  }

  /// Insert or replace a connection row by primary key.
  public func upsertConnection(_ record: ConnectionRecord) throws {
    try writer.write { db in
      try record.upsert(db)
    }
  }

  /// Delete a connection row by id.
  /// - Returns: `true` if a row was deleted, `false` if no such row existed.
  @discardableResult
  public func deleteConnection(id: UUID) throws -> Bool {
    try writer.write { db in
      try ConnectionRecord.deleteOne(db, key: id)
    }
  }

  /// Update only the `needs_auth` column on one row.
  ///
  /// No-op if the id doesn't match a row.
  public func setNeedsAuth(_ flag: Bool, forConnection id: UUID) throws {
    try writer.write { db in
      try db.execute(
        sql: "UPDATE server SET needs_auth = ? WHERE id = ?",
        arguments: [flag, id])
    }
  }

  /// An `AsyncSequence` of full connection-table snapshots, fired whenever
  /// the `server` table is written in this process. Backed by GRDB's
  /// `ValueObservation`; consumers don't see GRDB types.
  ///
  /// The first value is the current state (so callers can use this as both
  /// "initial hydrate" and "subsequent updates" in one loop). Cross-process
  /// changes (e.g. from the Share Extension) are not delivered live —
  /// foreground re-hydrate covers that, as called out in Stage 5 of the
  /// offline-cache plan.
  public func observeConnections() -> AsyncThrowingStream<[ConnectionRecord], Error> {
    let observation = ValueObservation.tracking(ConnectionRecord.fetchAll)
    let writer = writer
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await records in observation.values(in: writer) {
            continuation.yield(records)
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
