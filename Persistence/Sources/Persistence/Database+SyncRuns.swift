import Foundation
import GRDB

/// One sync step as the debug view sees it. Crosses the package boundary as a
/// value type; `trigger`, `step` and `outcome` are the raw strings AppShared
/// wrote.
public struct SyncRunEntry: Sendable, Equatable, Identifiable {
  public let id: Int64
  public let runID: UUID
  public let serverID: UUID?
  public let trigger: String
  public let step: String
  public let startedAt: Date
  public let endedAt: Date?
  public let outcome: String?
  public let message: String?
  public let succeeded: Int?
  public let failed: Int?

  /// Still running, or interrupted and not yet closed.
  public var isOpen: Bool { endedAt == nil }
}

/// The sync step record (`sync_run`). A step inserts its row when it starts and
/// fills in the outcome when it ends; the table is capped per server in the
/// same write as the insert, so it never grows past a fixed size.
///
/// Async only, like every cache table — see the rule in `Database+Connections`.
extension Database {
  /// Rows kept per server. An active day is a few hundred steps, so this is
  /// about a week of history for a busy server.
  public static let syncRunCapPerServer = 500
  /// Rows kept for background-task rows (`server_id` NULL).
  public static let syncRunCapForTasks = 200

  /// Insert an open row for a step that is starting; returns its id for
  /// ``endSyncStep``. Rows past the cap for the same server are dropped.
  public func beginSyncStep(
    runID: UUID, serverID: UUID?, trigger: String, step: String, at date: Date = Date()
  ) async throws -> Int64 {
    try await wrappingAsync("beginSyncStep") {
      try await writer.write { db in
        try SyncRunRecord(
          id: nil, runId: runID, serverId: serverID, trigger: trigger, step: step,
          startedAt: date.timeIntervalSinceReferenceDate
        ).insert(db)
        let id = db.lastInsertedRowID
        try Self.capSyncRuns(db, serverID: serverID)
        return id
      }
    }
  }

  /// Close a step's row with its outcome.
  public func endSyncStep(
    id: Int64, outcome: String, message: String? = nil, succeeded: Int? = nil,
    failed: Int? = nil, at date: Date = Date()
  ) async throws {
    try await wrappingAsync("endSyncStep") {
      try await writer.write { db in
        try db.execute(
          sql: """
            UPDATE sync_run
            SET ended_at = ?, outcome = ?, message = ?, succeeded = ?, failed = ?
            WHERE id = ?
            """,
          arguments: [date.timeIntervalSinceReferenceDate, outcome, message, succeeded, failed, id]
        )
      }
    }
  }

  /// Close every row started before `cutoff` and still open as `interrupted`.
  /// For launch, with the process's start as the cutoff: an open row older
  /// than the process is one its predecessor never finished.
  @discardableResult
  public func closeInterruptedSyncSteps(before cutoff: Date, at date: Date = Date()) async throws
    -> Int
  {
    try await wrappingAsync("closeInterruptedSyncSteps") {
      try await writer.write { db in
        try db.execute(
          sql: """
            UPDATE sync_run SET ended_at = ?, outcome = 'interrupted'
            WHERE ended_at IS NULL AND started_at < ?
            """,
          arguments: [date.timeIntervalSinceReferenceDate, cutoff.timeIntervalSinceReferenceDate])
        return db.changesCount
      }
    }
  }

  /// The newest rows across all servers, newest first.
  public func syncRuns(limit: Int = 1000) async throws -> [SyncRunEntry] {
    try await wrappingAsync("syncRuns") {
      try await writer.read { db in
        try SyncRunRecord
          .order(Column("started_at").desc, Column("id").desc)
          .limit(limit)
          .fetchAll(db)
          .map(SyncRunEntry.init)
      }
    }
  }

  public func clearSyncRuns() async throws {
    try await wrappingAsync("clearSyncRuns") {
      try await writer.write { db in
        try db.execute(sql: "DELETE FROM sync_run")
      }
    }
  }

  /// Keep the newest rows for `serverID` (or the task rows when nil).
  private static func capSyncRuns(_ db: GRDB.Database, serverID: UUID?) throws {
    let cap = serverID == nil ? syncRunCapForTasks : syncRunCapPerServer
    // `IS` matches NULL as well as a value.
    try db.execute(
      sql: """
        DELETE FROM sync_run
        WHERE id IN (
          SELECT id FROM sync_run
          WHERE server_id IS ?
          ORDER BY started_at DESC, id DESC
          LIMIT -1 OFFSET ?
        )
        """,
      arguments: [serverID, cap])
  }
}

extension SyncRunEntry {
  fileprivate init(_ record: SyncRunRecord) {
    self.init(
      id: record.id ?? 0,
      runID: record.runId,
      serverID: record.serverId,
      trigger: record.trigger,
      step: record.step,
      startedAt: Date(timeIntervalSinceReferenceDate: record.startedAt),
      endedAt: record.endedAt.map(Date.init(timeIntervalSinceReferenceDate:)),
      outcome: record.outcome,
      message: record.message,
      succeeded: record.succeeded,
      failed: record.failed)
  }
}
