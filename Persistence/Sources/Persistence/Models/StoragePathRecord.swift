import DataModel
import Foundation
import GRDB

/// GRDB record for a cached `StoragePath` (`storage_path` table).
public struct StoragePathRecord: Codable, Sendable, Equatable {
  public var serverId: UUID
  public var id: UInt
  public var name: String
  public var payload: Payload

  public struct Payload: Codable, Sendable, Equatable {
    public var path: String
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

extension StoragePathRecord: ElementRecord {
  public static let databaseTableName = "storage_path"

  public init(serverId: UUID, domain: StoragePath) {
    self.serverId = serverId
    id = domain.id
    name = domain.name
    payload = Payload(
      path: domain.path,
      slug: domain.slug,
      matchingAlgorithm: domain.matchingAlgorithm,
      match: domain.match,
      isInsensitive: domain.isInsensitive)
  }

  public var domain: StoragePath {
    StoragePath(
      id: id,
      name: name,
      path: payload.path,
      slug: payload.slug,
      matchingAlgorithm: payload.matchingAlgorithm,
      match: payload.match,
      isInsensitive: payload.isInsensitive)
  }
}
