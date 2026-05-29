import Common
import DataModel
import Foundation
import GRDB

/// GRDB record for a cached `Tag` (`tag` table, keyed `(server_id, id)`).
public struct TagRecord: Codable, Sendable, Equatable {
  public var serverId: UUID
  public var id: UInt
  public var name: String
  public var payload: Payload

  public struct Payload: Codable, Sendable, Equatable {
    public var isInboxTag: Bool
    public var slug: String
    public var color: HexColor
    public var match: String
    public var matchingAlgorithm: MatchingAlgorithm
    public var isInsensitive: Bool
    public var parent: UInt?
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case id
    case name
    case payload = "data"
  }
}

extension TagRecord: ElementRecord {
  public static let databaseTableName = "tag"

  public init(serverId: UUID, domain: Tag) {
    self.serverId = serverId
    id = domain.id
    name = domain.name
    payload = Payload(
      isInboxTag: domain.isInboxTag,
      slug: domain.slug,
      color: domain.color,
      match: domain.match,
      matchingAlgorithm: domain.matchingAlgorithm,
      isInsensitive: domain.isInsensitive,
      parent: domain.parent)
  }

  public var domain: Tag {
    Tag(
      id: id,
      isInboxTag: payload.isInboxTag,
      name: name,
      slug: payload.slug,
      color: payload.color,
      match: payload.match,
      matchingAlgorithm: payload.matchingAlgorithm,
      isInsensitive: payload.isInsensitive,
      parent: payload.parent)
  }
}
