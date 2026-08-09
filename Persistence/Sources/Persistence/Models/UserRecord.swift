import DataModel
import Foundation
import GRDB

/// GRDB record for a cached `User` (`user` table). `name` mirrors `username`.
public struct UserRecord: Codable, Sendable, Equatable {
  public var serverId: UUID
  public var id: UInt
  public var name: String
  public var payload: Payload

  public struct Payload: Codable, Sendable, Equatable {
    public var isSuperUser: Bool
    public var groups: [UInt]
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case id
    case name
    case payload = "data"
  }
}

extension UserRecord: ElementRecord {
  public static let databaseTableName = "user"

  public init(serverId: UUID, domain: User) {
    self.serverId = serverId
    id = domain.id
    name = domain.username
    payload = Payload(isSuperUser: domain.isSuperUser, groups: domain.groups)
  }

  public var domain: User {
    User(id: id, isSuperUser: payload.isSuperUser, username: name, groups: payload.groups)
  }
}
