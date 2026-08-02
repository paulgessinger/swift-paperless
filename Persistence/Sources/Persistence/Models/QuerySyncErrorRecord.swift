import Foundation
import GRDB

/// GRDB record for a row in the `query_sync_error` table (one per failed query).
///
/// Holds the last proactive-sync failure for a cached query, keyed by the same
/// `(server_id, query_key)` as `query_order`. `savedViewName` is `nil` for the
/// default list. The timestamp is `timeIntervalSinceReferenceDate` (REAL), like
/// the other regenerable sync cursors; cleared by `clearCache` and cascade-
/// deleted with its `server` row.
public struct QuerySyncErrorRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "query_sync_error"

  public var serverId: UUID
  public var queryKey: String
  public var savedViewName: String?
  public var message: String
  public var failedAt: Double

  public init(
    serverId: UUID, queryKey: String, savedViewName: String?, message: String,
    failedAt: Double
  ) {
    self.serverId = serverId
    self.queryKey = queryKey
    self.savedViewName = savedViewName
    self.message = message
    self.failedAt = failedAt
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case queryKey = "query_key"
    case savedViewName = "saved_view_name"
    case message = "message"
    case failedAt = "failed_at"
  }
}
