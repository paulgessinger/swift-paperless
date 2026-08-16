import Common
import Foundation
import GRDB
import os

/// Connection-table operations.
///
/// These are the only entry points `ConnectionManager` uses to read or
/// mutate `server` rows; GRDB stays hidden from AppShared and the rest of
/// the app. `Database+Elements` and `Database+Documents` are the analogous
/// APIs for the caches, under the same principle ("GRDB is sealed inside
/// Persistence").
extension Database {
  /// Fetch every connection row currently in the table.
  public func allConnections() throws(DatabaseError) -> [ConnectionRecord] {
    try wrapping("allConnections") {
      try wrapping("allConnections") {
        try writer.read { db in
          try ConnectionRecord.fetchAll(db)
        }
      }
    }
  }

  /// Fetch a single connection row by id, or `nil` if absent.
  public func connection(id: UUID) throws(DatabaseError) -> ConnectionRecord? {
    try wrapping("connection") {
      try writer.read { db in
        try ConnectionRecord.fetchOne(db, key: id)
      }
    }
  }

  /// Insert or replace a connection row by primary key.
  public func upsertConnection(_ record: ConnectionRecord) throws(DatabaseError) {
    try wrapping("upsertConnection") {
      try wrapping("upsertConnection") {
        try writer.write { db in
          try record.upsert(db)
        }
      }
    }
  }

  /// Delete a connection row by id.
  /// - Returns: `true` if a row was deleted, `false` if no such row existed.
  @discardableResult
  public func deleteConnection(id: UUID) throws(DatabaseError) -> Bool {
    try wrapping("deleteConnection") {
      try wrapping("deleteConnection") {
        try writer.write { db in
          try ConnectionRecord.deleteOne(db, key: id)
        }
      }
    }
  }

  /// Update only the `needs_auth` column on one row.
  ///
  /// No-op if the id doesn't match a row.
  public func setNeedsAuth(_ flag: Bool, forConnection id: UUID) throws(DatabaseError) {
    try wrapping("setNeedsAuth") {
      try wrapping("setNeedsAuth") {
        try writer.write { db in
          try db.execute(
            sql: "UPDATE server SET needs_auth = ? WHERE id = ?",
            arguments: [flag, id])
        }
      }
    }
  }

  /// An `AsyncSequence` of full connection-table snapshots, fired whenever
  /// the `server` table is written in this process. Backed by GRDB's
  /// `ValueObservation`; consumers don't see GRDB types.
  ///
  /// The first value is the current state (so callers can use this as both
  /// "initial hydrate" and "subsequent updates" in one loop). Cross-process
  /// changes (e.g. from the Share Extension) are not delivered live —
  /// foreground re-hydrate covers that.
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

// MARK: - Legacy UserDefaults export (debug seam)

extension Database {
  /// Write the current `server` table back out as the legacy `Connections`
  /// `UserDefaults` payload — the exact inverse of the v2 import migration.
  ///
  /// This exists to make ``Database/wipe(appGroupIdentifier:)`` testable. Once
  /// the app stores connections in GRDB, nothing writes the legacy payload any
  /// more, so a wipe has nothing to re-import and simply drops every server.
  /// Exporting first turns the wipe into a round trip: export → wipe →
  /// relaunch → the v2 migration re-imports what was exported.
  ///
  /// Tokens are unaffected either way — they live in the keychain keyed by
  /// URL + username, not in the database or in this payload.
  ///
  /// Overwrites any payload already under the key, and does nothing to the
  /// `needs_auth` flag, which the legacy shape can't express.
  ///
  /// - Returns: how many connections were written.
  @discardableResult
  public func exportConnectionsToLegacyUserDefaults(
    _ userDefaults: UserDefaults
  ) throws(DatabaseError) -> Int {
    try wrapping("exportConnectionsToLegacyUserDefaults") {
      let records = try allConnections()
      let legacy = Dictionary(
        uniqueKeysWithValues: records.map { ($0.id, LegacyStoredConnection(record: $0)) })
      try wrapping("exportConnectionsToLegacyUserDefaults") {
        let data = try JSONEncoder().encode(legacy)
        userDefaults.set(data, forKey: V2_ImportLegacyConnections.userDefaultsKey)
      }
      Logger.persistence.notice(
        "Exported \(records.count, privacy: .public) connection(s) to legacy UserDefaults")
      return records.count
    }
  }

  /// App-group convenience for ``exportConnectionsToLegacyUserDefaults(_:)``.
  @discardableResult
  public func exportConnectionsToLegacyUserDefaults(
    appGroupIdentifier: String = ContentStore.appGroup
  ) throws(DatabaseError) -> Int {
    try wrapping("exportConnectionsToLegacyUserDefaults") {
      guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
        throw DatabaseError.appGroupUnavailable(identifier: appGroupIdentifier)
      }
      return try exportConnectionsToLegacyUserDefaults(defaults)
    }
  }
}
