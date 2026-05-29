import DataModel
import Foundation
import GRDB

/// GRDB record for a cached `CustomField` (`custom_field` table).
///
/// `CustomFieldExtraData` is not itself `Codable`, so the payload mirrors its
/// fields (`selectOptions`, `defaultCurrency`) directly.
public struct CustomFieldRecord: Codable, Sendable, Equatable {
  public var serverId: UUID
  public var id: UInt
  public var name: String
  public var payload: Payload

  public struct Payload: Codable, Sendable, Equatable {
    public var dataType: CustomFieldDataType
    public var selectOptions: [CustomFieldSelectOption]
    public var defaultCurrency: String?
    public var documentCount: UInt?
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case id
    case name
    case payload = "data"
  }
}

extension CustomFieldRecord: ElementRecord {
  public static let databaseTableName = "custom_field"

  public init(serverId: UUID, domain: CustomField) {
    self.serverId = serverId
    id = domain.id
    name = domain.name
    payload = Payload(
      dataType: domain.dataType,
      selectOptions: domain.extraData.selectOptions,
      defaultCurrency: domain.extraData.defaultCurrency,
      documentCount: domain.documentCount)
  }

  public var domain: CustomField {
    CustomField(
      id: id,
      name: name,
      dataType: payload.dataType,
      extraData: CustomFieldExtraData(
        selectOptions: payload.selectOptions,
        defaultCurrency: payload.defaultCurrency),
      documentCount: payload.documentCount)
  }
}
