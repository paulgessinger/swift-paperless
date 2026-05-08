//
//  UISettingsModel.swift
//  DataModel
//
//  Created by Paul Gessinger on 26.12.24.
//

public struct UISettingsDocumentEditing: Sendable, Equatable {
  public var removeInboxTags: Bool

  public init(removeInboxTags: Bool = false) {
    self.removeInboxTags = removeInboxTags
  }
}

public struct UISettingsPermissions: Sendable, Equatable {
  public var defaultOwner: UInt?
  public var defaultViewUsers: [UInt]
  public var defaultViewGroups: [UInt]
  public var defaultEditUsers: [UInt]
  public var defaultEditGroups: [UInt]

  public init(
    defaultOwner: UInt? = nil,
    defaultViewUsers: [UInt] = [],
    defaultViewGroups: [UInt] = [],
    defaultEditUsers: [UInt] = [],
    defaultEditGroups: [UInt] = []
  ) {
    self.defaultOwner = defaultOwner
    self.defaultViewUsers = defaultViewUsers
    self.defaultViewGroups = defaultViewGroups
    self.defaultEditUsers = defaultEditUsers
    self.defaultEditGroups = defaultEditGroups
  }

  public func applyAsDefaults(to model: inout some PermissionsModel) {
    if case .unset = model.owner {
      model.owner = defaultOwner.map { .user($0) } ?? .none
    }

    var permissions = model.permissions ?? Permissions()
    permissions.view.users =
      permissions.view.users.isEmpty ? defaultViewUsers : permissions.view.users
    permissions.view.groups =
      permissions.view.groups.isEmpty ? defaultViewGroups : permissions.view.groups
    permissions.change.users =
      permissions.change.users.isEmpty ? defaultEditUsers : permissions.change.users
    permissions.change.groups =
      permissions.change.groups.isEmpty ? defaultEditGroups : permissions.change.groups
    model.permissions = permissions
  }

  public func appliedAsDefaults<T: PermissionsModel>(to model: T) -> T {
    var copy = model
    applyAsDefaults(to: &copy)
    return copy
  }
}

/// Saved view visibility (moved from per-view to UI settings in backend v3+).
/// Only the keys the app interacts with are modeled.
public struct UISettingsSavedViews: Sendable, Equatable {
  public var dashboardViewsVisibleIds: [UInt]
  public var sidebarViewsVisibleIds: [UInt]

  public init(
    dashboardViewsVisibleIds: [UInt] = [],
    sidebarViewsVisibleIds: [UInt] = []
  ) {
    self.dashboardViewsVisibleIds = dashboardViewsVisibleIds
    self.sidebarViewsVisibleIds = sidebarViewsVisibleIds
  }
}

public struct UISettingsSettings: Sendable, Equatable {
  public var documentEditing: UISettingsDocumentEditing
  public var permissions: UISettingsPermissions
  public var savedViews: UISettingsSavedViews
  public var appTitle: String?

  public init(
    documentEditing: UISettingsDocumentEditing = UISettingsDocumentEditing(),
    permissions: UISettingsPermissions = UISettingsPermissions(),
    savedViews: UISettingsSavedViews = UISettingsSavedViews(),
    appTitle: String? = nil
  ) {
    self.documentEditing = documentEditing
    self.permissions = permissions
    self.savedViews = savedViews
    self.appTitle = appTitle
  }
}

public struct UISettings: Sendable {
  public var user: User
  public var settings: UISettingsSettings
  public var permissions: UserPermissions

  public init(
    user: User,
    settings: UISettingsSettings = UISettingsSettings(),
    permissions: UserPermissions
  ) {
    self.user = user
    self.settings = settings
    self.permissions = permissions
  }
}
