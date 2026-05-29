import DataModel
import Foundation
import GRDB

/// GRDB record for a cached `UserGroup` (`user_group` table). The group has no
/// fields beyond `id`/`name`, so the `data` column carries an empty payload.
public struct UserGroupRecord: Codable, Sendable, Equatable {
  public var serverId: UUID
  public var id: UInt
  public var name: String
  public var payload: Payload

  public struct Payload: Codable, Sendable, Equatable {}

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case id
    case name
    case payload = "data"
  }
}

extension UserGroupRecord: ElementRecord {
  public static let databaseTableName = "user_group"

  public init(serverId: UUID, domain: UserGroup) {
    self.serverId = serverId
    id = domain.id
    name = domain.name
    payload = Payload()
  }

  public var domain: UserGroup {
    UserGroup(id: id, name: name)
  }
}
