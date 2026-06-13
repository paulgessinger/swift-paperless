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
  var default_owner: UInt?
  var default_view_users: [UInt]?
  var default_view_groups: [UInt]?
  var default_edit_users: [UInt]?
  var default_edit_groups: [UInt]?
}

extension ApiUISettingsPermissions {
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
