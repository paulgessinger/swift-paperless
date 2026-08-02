import DataModel
import Foundation
import GRDB

/// GRDB record for a cached `Correspondent` (`correspondent` table).
public struct CorrespondentRecord: Codable, Sendable, Equatable {
  public var serverId: UUID
  public var id: UInt
  public var name: String
  public var payload: Payload

  public struct Payload: Codable, Sendable, Equatable {
    public var documentCount: UInt?
    public var lastCorrespondence: Date?
    public var slug: String
    public var matchingAlgorithm: MatchingAlgorithm
    public var match: String
    public var isInsensitive: Bool
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case id
    case name
    case payload = "data"
  }
}

extension CorrespondentRecord: ElementRecord {
  public static let databaseTableName = "correspondent"

  public init(serverId: UUID, domain: Correspondent) {
    self.serverId = serverId
    id = domain.id
    name = domain.name
    payload = Payload(
      documentCount: domain.documentCount,
      lastCorrespondence: domain.lastCorrespondence,
      slug: domain.slug,
      matchingAlgorithm: domain.matchingAlgorithm,
      match: domain.match,
      isInsensitive: domain.isInsensitive)
  }

  public var domain: Correspondent {
    Correspondent(
      id: id,
      documentCount: payload.documentCount,
      lastCorrespondence: payload.lastCorrespondence,
      name: name,
      slug: payload.slug,
      matchingAlgorithm: payload.matchingAlgorithm,
      match: payload.match,
      isInsensitive: payload.isInsensitive)
  }
}
