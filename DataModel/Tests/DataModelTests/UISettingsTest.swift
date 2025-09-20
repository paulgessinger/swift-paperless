//
//  UISettingsTest.swift
//  DataModel
//
//  Created by Paul Gessinger on 26.12.24.
//

import Foundation
import Testing

@testable import DataModel

@Suite
struct UISettingsTest {
  @Test
  func testMinimumVersionDecode() throws {
    let data = try #require(testData("Data/UISettings/ui_settings_min_version.json"))
    let response = try JSONDecoder().decode(UISettings.self, from: data)
    #expect(response.user == User(id: 3, isSuperUser: true, username: "paperless"))
    let settings = response.settings
    #expect(!settings.documentEditing.removeInboxTags)

    // Test permissions
    let permissions = response.permissions
    #expect(permissions.test(.add, for: .tag))
    #expect(permissions.test(.view, for: .document))
    #expect(permissions.test(.change, for: .document))

    // Test some negative cases
    #expect(!permissions.test(.delete, for: .appConfig))
    #expect(!permissions.test(.add, for: .workflow))

    // Default permissions not present yet
    #expect(settings.permissions.defaultOwner == nil)
    #expect(settings.permissions.defaultViewUsers == [])
    #expect(settings.permissions.defaultViewGroups == [])
    #expect(settings.permissions.defaultEditUsers == [])
    #expect(settings.permissions.defaultEditGroups == [])
  }

  @Test
  func testDecode() throws {
    let data = try #require(testData("Data/UISettings/ui_settings_v2.13.5.json"))
    let response = try JSONDecoder().decode(UISettings.self, from: data)

    #expect(response.user == User(id: 2, isSuperUser: true, username: "paperless"))
    let settings = response.settings
    #expect(settings.documentEditing.removeInboxTags)

    // Test permissions
    let permissions = response.permissions
    #expect(permissions.test(.change, for: .savedView))
    #expect(permissions.test(.delete, for: .user))

    // Test full CRUD permissions for important resources
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
  }

  struct TestCorrespondent: PermissionsModel {
    var name: String
    var owner: Owner = .unset
    var permissions: Permissions?
  }

  @Test("Test application of UI settings permissions + owner to correspondent")
  func testApplyToCorrespondent() throws {
    let settingsPermissions = UISettingsPermissions(
      defaultOwner: 2, defaultViewUsers: [3], defaultViewGroups: [1], defaultEditUsers: [8],
      defaultEditGroups: [6])

    var correspondent = TestCorrespondent(name: "Aaaaaa")
    settingsPermissions.applyAsDefaults(to: &correspondent)
    #expect(correspondent.owner == .user(2))
    let perms = try #require(correspondent.permissions)
    #expect(perms.view.users == [3])
    #expect(perms.view.groups == [1])
    #expect(perms.change.users == [8])
    #expect(perms.change.groups == [6])
  }

  @Test("Explicit owner and permissions override settings defaults")
  func testExplicitOwnerAndPermissionsOverrideSettingsDefaults() throws {
    let settingsPermissions = UISettingsPermissions(
      defaultOwner: 2, defaultViewUsers: [3], defaultViewGroups: [1], defaultEditUsers: [8],
      defaultEditGroups: [6])

    let correspondent = TestCorrespondent(
      name: "Aaaaaa", owner: .user(1),
      permissions: Permissions(
        view: .init(users: [4], groups: [2]), change: .init(users: [9], groups: [7])))
    let applied = settingsPermissions.appliedAsDefaults(to: correspondent)
    #expect(applied.owner == .user(1))
    let perms = try #require(applied.permissions)
    #expect(perms.view.users == [4])
    #expect(perms.view.groups == [2])
    #expect(perms.change.users == [9])
    #expect(perms.change.groups == [7])
  }

  @Test("Partial permission overrides work correctly")
  func testPartialPermissionOverrides() throws {
    let settingsPermissions = UISettingsPermissions(
      defaultOwner: 2, defaultViewUsers: [3], defaultViewGroups: [1], defaultEditUsers: [8],
      defaultEditGroups: [6])

    // Only override some permissions, let others fall back to defaults
    let correspondent = TestCorrespondent(
      name: "Aaaaaa", owner: .unset,
      permissions: Permissions(
        view: .init(users: [4], groups: []), change: .init(users: [], groups: [7])))
    let applied = settingsPermissions.appliedAsDefaults(to: correspondent)

    #expect(applied.owner == .user(2))  // Falls back to default
    let perms = try #require(applied.permissions)
    #expect(perms.view.users == [4])  // explicitly set
    #expect(perms.view.groups == [1])  // falls back to default
    #expect(perms.change.users == [8])  // falls back to default
    #expect(perms.change.groups == [7])  // explicitly set
  }

  @Test("Test explicit none owner")
  func testExplicitNoneOwner() throws {
    let settingsPermissions = UISettingsPermissions(
      defaultOwner: 2, defaultViewUsers: [3], defaultViewGroups: [1], defaultEditUsers: [8],
      defaultEditGroups: [6])

    let correspondent = TestCorrespondent(
      name: "Aaaaaa", owner: .none,
      permissions: Permissions(
        view: .init(users: [4], groups: [2]), change: .init(users: [9], groups: [7])))
    let applied = settingsPermissions.appliedAsDefaults(to: correspondent)
    #expect(applied.owner == .none)  // Explicit none owner overrides default
  }
}
