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

  /// Whether the document `document` on the server `server` is kept, on its
  /// own or by a kept saved view that lists it: the correlated test the
  /// protections that ask "is this kept" share. The query-interface twin of
  /// `Database.keptOfflineExists`.
  static func isKept(server: SQLExpression, document: SQLExpression) -> SQLExpression {
    let alone = filter(Column("server_id") == server && Column("document_id") == document)
    let keptViewKeys =
      KeptOfflineViewRecord
      .filter(Column("server_id") == server)
      .select(Column("query_key"))
    let listed = QueryOrderRow.filter(
      Column("server_id") == server && Column("remote_id") == document
        && keptViewKeys.contains(Column("query_key")))
    return alone.exists() || listed.exists()
  }
}
