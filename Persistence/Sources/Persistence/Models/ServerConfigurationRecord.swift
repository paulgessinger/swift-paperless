import DataModel
import Foundation
import GRDB

/// GRDB record for the per-server `ServerConfiguration` singleton
/// (`server_configuration` table, keyed by `server_id`).
public struct ServerConfigurationRecord: Codable, Sendable, Equatable {
  public var serverId: UUID
  public var payload: Payload

  public struct Payload: Codable, Sendable, Equatable {
    public var id: UInt
    public var barcodeAsnPrefix: String?
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case payload = "data"
  }
}

extension ServerConfigurationRecord: FetchableRecord, PersistableRecord, TableRecord {
  public static let databaseTableName = "server_configuration"

  public static func databaseJSONEncoder(for column: String) -> JSONEncoder {
    ElementStorage.encoder
  }

  public static func databaseJSONDecoder(for column: String) -> JSONDecoder {
    ElementStorage.decoder
  }

  public init(serverId: UUID, domain: ServerConfiguration) {
    self.serverId = serverId
    payload = Payload(id: domain.id, barcodeAsnPrefix: domain.barcodeAsnPrefix)
  }

  public var domain: ServerConfiguration {
    ServerConfiguration(id: payload.id, barcodeAsnPrefix: payload.barcodeAsnPrefix)
  }
}
