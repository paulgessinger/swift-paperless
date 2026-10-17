import Foundation
import GRDB

/// GRDB record for a row in the `kept_offline` table: one document the user
/// keeps on the device. `keptAt` is `timeIntervalSinceReferenceDate` (REAL).
public struct KeptOfflineRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "kept_offline"

  public var serverId: UUID
  public var documentId: UInt
  public var keptAt: Double

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case documentId = "document_id"
    case keptAt = "kept_at"
  }

  /// The membership rows for the document `document` on the server `server`,
  /// for a correlated `EXISTS` in the protections that ask "is this kept".
  static func keeping(server: SQLExpression, document: SQLExpression)
    -> QueryInterfaceRequest<KeptOfflineRecord>
  {
    filter(Column("server_id") == server && Column("document_id") == document)
  }
}
