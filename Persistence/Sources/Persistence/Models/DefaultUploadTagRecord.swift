import Foundation
import GRDB

/// GRDB record for a row in the `default_upload_tag` table: one tag preselected
/// when uploading to a server.
public struct DefaultUploadTagRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "default_upload_tag"

  public var serverId: UUID
  public var tagId: UInt

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case tagId = "tag_id"
  }
}
