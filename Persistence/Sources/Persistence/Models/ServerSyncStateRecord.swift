import Foundation
import GRDB

/// GRDB record for a row in the `server_sync_state` table (one per server).
///
/// Holds *regenerable* per-server sync cursors — the changed-metadata delta
/// watermark, the proactive full-library fill's completed-at, and when the
/// reconcile last refreshed something — kept separate
/// from the durable connection config in `server`. Timestamps are stored as
/// `timeIntervalSinceReferenceDate` (REAL) so the precision-sensitive delta
/// comparison round-trips exactly. Cleared by `clearCache` and cascade-deleted
/// with its `server` row.
public struct ServerSyncStateRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "server_sync_state"

  public var serverId: UUID
  public var deltaWatermark: Double?
  public var libraryCoverageAt: Double?
  public var lastRefreshedAt: Double?

  public init(
    serverId: UUID, deltaWatermark: Double? = nil, libraryCoverageAt: Double? = nil,
    lastRefreshedAt: Double? = nil
  ) {
    self.serverId = serverId
    self.deltaWatermark = deltaWatermark
    self.libraryCoverageAt = libraryCoverageAt
    self.lastRefreshedAt = lastRefreshedAt
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case deltaWatermark = "delta_watermark"
    case libraryCoverageAt = "library_coverage_at"
    case lastRefreshedAt = "last_refreshed_at"
  }
}
