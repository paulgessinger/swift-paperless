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
