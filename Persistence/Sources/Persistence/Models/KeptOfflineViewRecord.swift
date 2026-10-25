import Foundation
import GRDB

/// GRDB record for a row in the `kept_offline_view` table: one saved view the
/// user keeps on the device. `keptAt` is `timeIntervalSinceReferenceDate` (REAL).
public struct KeptOfflineViewRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "kept_offline_view"

  public var serverId: UUID
  public var savedViewId: UInt
  public var keptAt: Double

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case savedViewId = "saved_view_id"
    case keptAt = "kept_at"
  }
}
