import Foundation
import GRDB

/// GRDB record for a row in the `sync_run` table (one per sync step execution).
///
/// `trigger`, `step` and `outcome` are stored as strings so `Persistence` stays
/// free of AppShared's enums, like `ConnectionRecord.offlineBrowsingMode`.
/// Timestamps are `timeIntervalSinceReferenceDate` (REAL).
public struct SyncRunRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "sync_run"

  public var id: Int64?
  public var runId: UUID
  public var serverId: UUID?
  public var trigger: String
  public var step: String
  public var startedAt: Double
  public var endedAt: Double?
  public var outcome: String?
  public var message: String?
  public var succeeded: Int?
  public var failed: Int?

  enum CodingKeys: String, CodingKey {
    case id
    case runId = "run_id"
    case serverId = "server_id"
    case trigger
    case step
    case startedAt = "started_at"
    case endedAt = "ended_at"
    case outcome
    case message
    case succeeded
    case failed
  }
}
