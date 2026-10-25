import Foundation
import GRDB

/// GRDB record for a row in the `kept_offline` table: one reason a document is
/// kept on the device, on its own (`savedViewId` 0) or by a kept saved view.
/// `keptAt` is `timeIntervalSinceReferenceDate` (REAL).
public struct KeptOfflineRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "kept_offline"

  public var serverId: UUID
  public var documentId: UInt
  /// 0 for a document kept on its own; otherwise the kept saved view that
  /// keeps it.
  public var savedViewId: UInt = 0
  public var keptAt: Double

  /// `savedViewId` of a document kept on its own.
  public static let onItsOwn: UInt = 0

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case documentId = "document_id"
    case savedViewId = "saved_view_id"
    case keptAt = "kept_at"
  }

  /// The membership rows for the document `document` on the server `server`,
  /// for a correlated `EXISTS` in the protections that ask "is this kept":
  /// any row, on its own or by a kept view.
  static func keeping(server: SQLExpression, document: SQLExpression)
    -> QueryInterfaceRequest<KeptOfflineRecord>
  {
    filter(Column("server_id") == server && Column("document_id") == document)
  }
}
