//
//  UserModelTest.swift
//  DataModel
//
//  Created by Assistant on 03.03.24.
//

import Common
@testable import DataModel
import Foundation
import Testing

private let tz = TimeZone(secondsFromGMT: 60 * 60)!
private let decoder = makeDecoder(tz: tz)

private struct Dummy: PermissionsModel {
    var owner: Owner
    var permissions: Permissions?
}

@Suite
struct UserModelTest {
    @Test func testDecoding() throws {
        let data = try #require(testData("Data/users.json"))
        let users = try decoder.decode([User].self, from: data)

        // Test regular user
        #expect(users[0].id == 42)
        #expect(users[0].username == "testuser123")
        #expect(users[0].isSuperUser == false)
        #expect(users[0].groups == [1, 3, 5])

        // Test admin user
        #expect(users[1].id == 77)
        #expect(users[1].username == "admin")
        #expect(users[1].isSuperUser == true)
        #expect(users[1].groups == [1])
    }

    @Test func testUserGroup() throws {
        let jsonData = """
        {
            "id": 7,
            "name": "Administrators"
        }
        """.data(using: .utf8)!

        let group = try decoder.decode(UserGroup.self, from: jsonData)

        #expect(group.id == 7)
        #expect(group.name == "Administrators")
    }

    @Test func testCanChange() throws {
        let user = User(id: 1, isSuperUser: false, username: "user", groups: [2, 3])
        let superUser = User(id: 2, isSuperUser: true, username: "superuser")

        // Test superuser always has permission
        var dummyResource = Dummy(owner: .none, permissions: nil)
        #expect(superUser.canChange(dummyResource))
        // Resource without owner is accessible to all
        #expect(user.canChange(dummyResource))

        // Test resource without owner is accessible to all
        dummyResource = Dummy(owner: .none, permissions: Permissions(view: .init(), change: .init()))
        #expect(superUser.canChange(dummyResource))
        #expect(user.canChange(dummyResource))

        // Test user with direct permission
        dummyResource = Dummy(owner: .user(5), permissions: Permissions(view: .init(), change: .init(users: [1], groups: [])))
        #expect(user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))

        // Test user is owner of resource
        dummyResource = Dummy(owner: .user(1), permissions: Permissions(view: .init(), change: .init()))
        #expect(user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))

        // Test user in group with permission
        dummyResource = Dummy(owner: .user(5), permissions: Permissions(view: .init(), change: .init(users: [], groups: [2])))
        #expect(user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))

        // Test another user has explicit permission
        dummyResource = Dummy(owner: .user(5), permissions: Permissions(view: .init(), change: .init(users: [7], groups: [])))
        #expect(!user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))

        // Test another group has permission
        dummyResource = Dummy(owner: .user(5), permissions: Permissions(view: .init(), change: .init(users: [], groups: [7])))
        #expect(!user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))

        // Test user without any permissions
        dummyResource = Dummy(owner: .user(5), permissions: Permissions(view: .none, change: .none))
        #expect(!user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))

        // Test nil permissions returns false for normal user but true for superuser
        dummyResource = Dummy(owner: .user(5), permissions: nil)
        #expect(!user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))
    }

    @Test func testCanView() throws {
        let user = User(id: 1, isSuperUser: false, username: "user", groups: [2, 3])
        let superUser = User(id: 2, isSuperUser: true, username: "superuser")

        // Test superuser always has permission
        var dummyResource = Dummy(owner: .none, permissions: nil)
        #expect(superUser.canView(dummyResource))
        // Resource without owner is accessible to all
        #expect(user.canView(dummyResource))

        // Test resource without owner is accessible to all
        dummyResource = Dummy(owner: .unset, permissions: Permissions(view: .none, change: .none))
        #expect(superUser.canView(dummyResource))
        #expect(user.canView(dummyResource))

        // Test user with direct permission
        dummyResource = Dummy(owner: .user(5), permissions: Permissions(view: .init(users: [1], groups: []), change: .none))
        #expect(user.canView(dummyResource))
        #expect(superUser.canView(dummyResource))

        // Test user is owner of resource
        dummyResource = Dummy(owner: .user(1), permissions: Permissions(view: .init(), change: .none))
        #expect(user.canView(dummyResource))
        #expect(superUser.canView(dummyResource))

        // Test user in group with permission
        dummyResource = Dummy(owner: .user(5), permissions: Permissions(view: .init(users: [], groups: [2]), change: .none))
        #expect(user.canView(dummyResource))
        #expect(superUser.canView(dummyResource))

        // Test another user has explicit permission
        dummyResource = Dummy(owner: .user(5), permissions: Permissions(view: .init(users: [7], groups: []), change: .none))
        #expect(!user.canView(dummyResource))
        #expect(superUser.canView(dummyResource))

        // Test another group has permission
        dummyResource = Dummy(owner: .user(5), permissions: Permissions(view: .init(users: [], groups: [7]), change: .none))
        #expect(!user.canView(dummyResource))
        #expect(superUser.canView(dummyResource))

        // Test user without any permissions
        dummyResource = Dummy(owner: .user(5), permissions: Permissions(view: .none, change: .none))
        #expect(!user.canView(dummyResource))
        #expect(superUser.canView(dummyResource))

        // Test nil permissions returns false for normal user but true for superuser
        dummyResource = Dummy(owner: .user(5), permissions: nil)
        #expect(!user.canView(dummyResource))
        #expect(superUser.canView(dummyResource))
    }

    @Test func testChangeImpliesView() throws {
        let user = User(id: 1, isSuperUser: false, username: "user", groups: [2])

        // Test user with only change permission can view
        var dummyResource = Dummy(owner: .user(5), permissions: Permissions(
            view: .init(users: [], groups: []),
            change: .init(users: [1], groups: [])
        ))
        #expect(user.canView(dummyResource))

        // Test user in group with only change permission can view
        dummyResource = Dummy(owner: .user(5), permissions: Permissions(
            view: .init(users: [], groups: []),
            change: .init(users: [], groups: [2])
        ))
        #expect(user.canView(dummyResource))

        // Verify that the reverse is not true (view doesn't imply change)
        dummyResource = Dummy(owner: .user(5), permissions: Permissions(
            view: .init(users: [1], groups: []),
            change: .init(users: [], groups: [])
        ))
        #expect(user.canView(dummyResource))
        #expect(!user.canChange(dummyResource))

        dummyResource = Dummy(owner: .user(5), permissions: Permissions(
            view: .init(users: [], groups: [2]),
            change: .init(users: [], groups: [])
        ))
        #expect(user.canView(dummyResource))
        #expect(!user.canChange(dummyResource))
    }
}
