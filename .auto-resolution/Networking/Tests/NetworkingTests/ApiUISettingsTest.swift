//
//  ApiUISettingsTest.swift
//  Networking
//

import DataModel
import Foundation
import Testing

@testable import Networking

@Suite
struct ApiUISettingsTest {
  @Test
  func testMinimumVersionDecode() throws {
    let data = try #require(testData("Data/UISettings/ui_settings_min_version.json"))
    let response = try JSONDecoder().decode(ApiUISettings.self, from: data).domain

    #expect(response.user == User(id: 3, isSuperUser: true, username: "paperless"))
    let settings = response.settings
    #expect(!settings.documentEditing.removeInboxTags)

    let permissions = response.permissions
    #expect(permissions.test(.add, for: .tag))
    #expect(permissions.test(.view, for: .document))
    #expect(permissions.test(.change, for: .document))

    #expect(!permissions.test(.delete, for: .shareLink))
    #expect(!permissions.test(.add, for: .workflow))

    #expect(settings.permissions.defaultOwner == nil)
    #expect(settings.permissions.defaultViewUsers == [])
    #expect(settings.permissions.defaultViewGroups == [])
    #expect(settings.permissions.defaultEditUsers == [])
    #expect(settings.permissions.defaultEditGroups == [])

    // app_title not present in this older response: should decode to nil
    #expect(settings.appTitle == nil)
  }

  @Test
  func testDecode() throws {
    let data = try #require(testData("Data/UISettings/ui_settings_v2.13.5.json"))
    let response = try JSONDecoder().decode(ApiUISettings.self, from: data).domain

    #expect(response.user == User(id: 2, isSuperUser: true, username: "paperless"))
    let settings = response.settings
    #expect(settings.documentEditing.removeInboxTags)

    let permissions = response.permissions
    #expect(permissions.test(.change, for: .savedView))
    #expect(permissions.test(.delete, for: .user))

    let crudResources: [UserPermissions.Resource] = [.document, .tag]
    for resource in crudResources {
      #expect(permissions.test(.view, for: resource))
      #expect(permissions.test(.add, for: resource))
      #expect(permissions.test(.change, for: resource))
      #expect(permissions.test(.delete, for: resource))
    }

    #expect(settings.permissions.defaultOwner == 123)
    #expect(settings.permissions.defaultViewUsers == [])
    #expect(settings.permissions.defaultViewGroups == [1])
    #expect(settings.permissions.defaultEditUsers == [])
    #expect(settings.permissions.defaultEditGroups == [6])

    // app_title is present but null in v2.13.5: should decode to nil
    #expect(settings.appTitle == nil)
  }

  @Test
  func testSavedViewsDecode() throws {
    let data = try #require(testData("Data/UISettings/ui_settings_v3.0.0_api_v10.json"))
    let response = try JSONDecoder().decode(ApiUISettings.self, from: data).domain

    let savedViews = response.settings.savedViews
    #expect(savedViews.dashboardViewsVisibleIds == [7])
    #expect(savedViews.sidebarViewsVisibleIds == [7])
  }

  @Test
  func testSavedViewsDecodePartial() throws {
    // v2.13.5 has saved_views with only warn_on_unsaved_change; visibility IDs default to []
    let data = try #require(testData("Data/UISettings/ui_settings_v2.13.5.json"))
    let response = try JSONDecoder().decode(ApiUISettings.self, from: data).domain

    let savedViews = response.settings.savedViews
    #expect(savedViews.dashboardViewsVisibleIds == [])
    #expect(savedViews.sidebarViewsVisibleIds == [])
  }

  @Test
  func testSavedViewsEncodeRoundTrip() throws {
    let savedViews = UISettingsSavedViews(
      dashboardViewsVisibleIds: [7, 10],
      sidebarViewsVisibleIds: [7]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try encoder.encode(ApiUISettingsSavedViews(from: savedViews))
    let decoded = try JSONDecoder().decode(ApiUISettingsSavedViews.self, from: encoded).domain

    #expect(decoded.dashboardViewsVisibleIds == savedViews.dashboardViewsVisibleIds)
    #expect(decoded.sidebarViewsVisibleIds == savedViews.sidebarViewsVisibleIds)
  }

  @Test("app_title decodes when present as a string")
  func testAppTitleDecodes() throws {
    let json = """
      {
        "user": {"id": 1, "username": "paperless", "is_staff": true, "is_superuser": true, "groups": []},
        "settings": {"app_title": "My Paperless"},
        "permissions": []
      }
      """.data(using: .utf8)!
    let response = try JSONDecoder().decode(ApiUISettings.self, from: json).domain
    #expect(response.settings.appTitle == "My Paperless")
  }
}
