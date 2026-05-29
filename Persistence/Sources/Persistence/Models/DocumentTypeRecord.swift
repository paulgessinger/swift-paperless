import DataModel
import Foundation
import GRDB

/// GRDB record for a cached `DocumentType` (`document_type` table).
public struct DocumentTypeRecord: Codable, Sendable, Equatable {
  public var serverId: UUID
  public var id: UInt
  public var name: String
  public var payload: Payload

  public struct Payload: Codable, Sendable, Equatable {
    public var slug: String
    public var match: String
    public var matchingAlgorithm: MatchingAlgorithm
    public var isInsensitive: Bool
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case id
    case name
    case payload = "data"
  }
}

extension DocumentTypeRecord: ElementRecord {
  public static let databaseTableName = "document_type"

  public init(serverId: UUID, domain: DocumentType) {
    self.serverId = serverId
    id = domain.id
    name = domain.name
    payload = Payload(
      slug: domain.slug,
      match: domain.match,
      matchingAlgorithm: domain.matchingAlgorithm,
      isInsensitive: domain.isInsensitive)
  }

  public var domain: DocumentType {
    DocumentType(
      id: id,
      name: name,
      slug: payload.slug,
      match: payload.match,
      matchingAlgorithm: payload.matchingAlgorithm,
      isInsensitive: payload.isInsensitive)
  }
}
