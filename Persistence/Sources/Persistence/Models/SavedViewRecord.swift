import DataModel
import Foundation
import GRDB

/// GRDB record for a cached `SavedView` (`saved_view` table).
///
/// The view's settings, filter rules, sort, owner and permissions all live in
/// the JSON `data` column — they're stored as opaque blobs here and only
/// interpreted by the domain layer.
public struct SavedViewRecord: Codable, Sendable, Equatable {
  public var serverId: UUID
  public var id: UInt
  public var name: String
  public var payload: Payload

  public struct Payload: Codable, Sendable, Equatable {
    public var showOnDashboard: Bool
    public var showInSidebar: Bool
    public var sortField: SortField?
    public var sortOrder: DataModel.SortOrder
    public var filterRules: [FilterRule]
    public var owner: Owner
    public var permissions: Permissions?
    public var setPermissions: Permissions?
    public var userCanChange: Bool
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case id
    case name
    case payload = "data"
  }
}

extension SavedViewRecord: ElementRecord {
  public static let databaseTableName = "saved_view"

  public init(serverId: UUID, domain: SavedView) {
    self.serverId = serverId
    id = domain.id
    name = domain.name
    payload = Payload(
      showOnDashboard: domain.showOnDashboard,
      showInSidebar: domain.showInSidebar,
      sortField: domain.sortField,
      sortOrder: domain.sortOrder,
      filterRules: domain.filterRules,
      owner: domain.owner,
      permissions: domain.permissions,
      setPermissions: domain.setPermissions,
      userCanChange: domain.userCanChange)
  }

  public var domain: SavedView {
    SavedView(
      id: id,
      name: name,
      showOnDashboard: payload.showOnDashboard,
      showInSidebar: payload.showInSidebar,
      sortField: payload.sortField,
      sortOrder: payload.sortOrder,
      filterRules: payload.filterRules,
      owner: payload.owner,
      permissions: payload.permissions,
      setPermissions: payload.setPermissions,
      userCanChange: payload.userCanChange)
  }
}
