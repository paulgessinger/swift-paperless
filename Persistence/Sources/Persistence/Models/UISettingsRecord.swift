import DataModel
import Foundation
import GRDB

/// GRDB record for the per-server `UISettings` singleton (`ui_settings` table,
/// keyed by `server_id`). Caching this keeps the current user, app settings and
/// the permission matrix available offline — without it, an offline cold start
/// would fall back to assuming full permissions.
///
/// None of `User`, `UISettingsSettings` or `UserPermissions` are `Codable`, so
/// the payload mirrors their fields. The permission matrix is stored as
/// `resource.rawValue → [view, add, change, delete]` (indexed by
/// `Operation.rawValue`) and round-tripped through the public `test`/`set` API.
public struct UISettingsRecord: Codable, Sendable {
  public var serverId: UUID
  public var payload: Payload

  public struct Payload: Codable, Sendable {
    public var user: UserData
    public var settings: SettingsData
    public var permissions: [String: [Bool]]

    public struct UserData: Codable, Sendable {
      public var id: UInt
      public var isSuperUser: Bool
      public var username: String
      public var groups: [UInt]
    }

    public struct SettingsData: Codable, Sendable {
      public var removeInboxTags: Bool
      public var defaultOwner: UInt?
      public var defaultViewUsers: [UInt]
      public var defaultViewGroups: [UInt]
      public var defaultEditUsers: [UInt]
      public var defaultEditGroups: [UInt]
      public var dashboardViewsVisibleIds: [UInt]
      public var sidebarViewsVisibleIds: [UInt]
      public var appTitle: String?
    }
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case payload = "data"
  }
}

extension UISettingsRecord: FetchableRecord, PersistableRecord, TableRecord {
  public static let databaseTableName = "ui_settings"

  public static func databaseJSONEncoder(for column: String) -> JSONEncoder {
    ElementStorage.encoder
  }

  public static func databaseJSONDecoder(for column: String) -> JSONDecoder {
    ElementStorage.decoder
  }

  public init(serverId: UUID, domain: UISettings) {
    self.serverId = serverId

    var permissions = [String: [Bool]]()
    for resource in UserPermissions.Resource.allCases {
      permissions[resource.rawValue] = UserPermissions.Operation.allCases.map {
        domain.permissions.test($0, for: resource)
      }
    }

    payload = Payload(
      user: Payload.UserData(
        id: domain.user.id,
        isSuperUser: domain.user.isSuperUser,
        username: domain.user.username,
        groups: domain.user.groups),
      settings: Payload.SettingsData(
        removeInboxTags: domain.settings.documentEditing.removeInboxTags,
        defaultOwner: domain.settings.permissions.defaultOwner,
        defaultViewUsers: domain.settings.permissions.defaultViewUsers,
        defaultViewGroups: domain.settings.permissions.defaultViewGroups,
        defaultEditUsers: domain.settings.permissions.defaultEditUsers,
        defaultEditGroups: domain.settings.permissions.defaultEditGroups,
        dashboardViewsVisibleIds: domain.settings.savedViews.dashboardViewsVisibleIds,
        sidebarViewsVisibleIds: domain.settings.savedViews.sidebarViewsVisibleIds,
        appTitle: domain.settings.appTitle),
      permissions: permissions)
  }

  public var domain: UISettings {
    var permissions = UserPermissions.empty
    for (rawResource, flags) in payload.permissions {
      guard let resource = UserPermissions.Resource(rawValue: rawResource) else { continue }
      for operation in UserPermissions.Operation.allCases where operation.rawValue < flags.count {
        permissions.set(operation, to: flags[operation.rawValue], for: resource)
      }
    }

    let user = User(
      id: payload.user.id,
      isSuperUser: payload.user.isSuperUser,
      username: payload.user.username,
      groups: payload.user.groups)

    let settings = UISettingsSettings(
      documentEditing: UISettingsDocumentEditing(
        removeInboxTags: payload.settings.removeInboxTags),
      permissions: UISettingsPermissions(
        defaultOwner: payload.settings.defaultOwner,
        defaultViewUsers: payload.settings.defaultViewUsers,
        defaultViewGroups: payload.settings.defaultViewGroups,
        defaultEditUsers: payload.settings.defaultEditUsers,
        defaultEditGroups: payload.settings.defaultEditGroups),
      savedViews: UISettingsSavedViews(
        dashboardViewsVisibleIds: payload.settings.dashboardViewsVisibleIds,
        sidebarViewsVisibleIds: payload.settings.sidebarViewsVisibleIds),
      appTitle: payload.settings.appTitle)

    return UISettings(user: user, settings: settings, permissions: permissions)
  }
}
