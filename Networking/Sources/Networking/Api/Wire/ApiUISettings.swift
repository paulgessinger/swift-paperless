//
//  ApiUISettings.swift
//  Networking
//

import DataModel
import Foundation

// MARK: - Wire types for the /api/ui_settings endpoint

struct ApiUISettings: Decodable, Sendable {
  var user: ApiUser
  var settings: ApiUISettingsSettings?
  var permissions: ApiUserPermissions?
}

extension ApiUISettings {
  var domain: UISettings {
    UISettings(
      user: user.domain,
      settings: settings?.domain ?? UISettingsSettings(),
      permissions: permissions?.domain ?? .empty
    )
  }
}

struct ApiUISettingsSettings: Codable, Sendable {
  var document_editing: ApiUISettingsDocumentEditing?
  var permissions: ApiUISettingsPermissions?
  var saved_views: ApiUISettingsSavedViews?
  var app_title: String?
}

extension ApiUISettingsSettings {
  var domain: UISettingsSettings {
    UISettingsSettings(
      documentEditing: document_editing?.domain ?? UISettingsDocumentEditing(),
      permissions: permissions?.domain ?? UISettingsPermissions(),
      savedViews: saved_views?.domain ?? UISettingsSavedViews(),
      appTitle: app_title
    )
  }

  init(from domain: UISettingsSettings) {
    document_editing = ApiUISettingsDocumentEditing(from: domain.documentEditing)
    permissions = ApiUISettingsPermissions(from: domain.permissions)
    saved_views = ApiUISettingsSavedViews(from: domain.savedViews)
    app_title = domain.appTitle
  }
}

struct ApiUISettingsDocumentEditing: Codable, Sendable {
  var remove_inbox_tags: Bool?
}

extension ApiUISettingsDocumentEditing {
  var domain: UISettingsDocumentEditing {
    UISettingsDocumentEditing(removeInboxTags: remove_inbox_tags ?? false)
  }

  init(from domain: UISettingsDocumentEditing) {
    remove_inbox_tags = domain.removeInboxTags
  }
}

struct ApiUISettingsPermissions: Codable, Sendable {
  // Tri-state: absent is `.unset` (the creating user), `null` is `.none`.
  var default_owner: Owner
  var default_view_users: [UInt]?
  var default_view_groups: [UInt]?
  var default_edit_users: [UInt]?
  var default_edit_groups: [UInt]?

  // Required because of the custom init(from:) and encode(to:) below, which
  // tell an absent `default_owner` apart from `null`.
  enum CodingKeys: String, CodingKey {
    case default_owner, default_view_users, default_view_groups
    case default_edit_users, default_edit_groups
  }
}

extension ApiUISettingsPermissions {
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    default_owner =
      container.contains(.default_owner)
      ? try container.decode(Owner.self, forKey: .default_owner) : .unset
    default_view_users = try container.decodeIfPresent([UInt].self, forKey: .default_view_users)
    default_view_groups = try container.decodeIfPresent([UInt].self, forKey: .default_view_groups)
    default_edit_users = try container.decodeIfPresent([UInt].self, forKey: .default_edit_users)
    default_edit_groups = try container.decodeIfPresent([UInt].self, forKey: .default_edit_groups)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if default_owner != .unset {
      try container.encode(default_owner, forKey: .default_owner)
    }
    try container.encodeIfPresent(default_view_users, forKey: .default_view_users)
    try container.encodeIfPresent(default_view_groups, forKey: .default_view_groups)
    try container.encodeIfPresent(default_edit_users, forKey: .default_edit_users)
    try container.encodeIfPresent(default_edit_groups, forKey: .default_edit_groups)
  }

  var domain: UISettingsPermissions {
    UISettingsPermissions(
      defaultOwner: default_owner,
      defaultViewUsers: default_view_users ?? [],
      defaultViewGroups: default_view_groups ?? [],
      defaultEditUsers: default_edit_users ?? [],
      defaultEditGroups: default_edit_groups ?? []
    )
  }

  init(from domain: UISettingsPermissions) {
    default_owner = domain.defaultOwner
    default_view_users = domain.defaultViewUsers
    default_view_groups = domain.defaultViewGroups
    default_edit_users = domain.defaultEditUsers
    default_edit_groups = domain.defaultEditGroups
  }
}

struct ApiUISettingsSavedViews: Codable, Sendable {
  var dashboard_views_visible_ids: [UInt]?
  var sidebar_views_visible_ids: [UInt]?
}

extension ApiUISettingsSavedViews {
  var domain: UISettingsSavedViews {
    UISettingsSavedViews(
      dashboardViewsVisibleIds: dashboard_views_visible_ids ?? [],
      sidebarViewsVisibleIds: sidebar_views_visible_ids ?? []
    )
  }

  init(from domain: UISettingsSavedViews) {
    dashboard_views_visible_ids = domain.dashboardViewsVisibleIds
    sidebar_views_visible_ids = domain.sidebarViewsVisibleIds
  }
}
