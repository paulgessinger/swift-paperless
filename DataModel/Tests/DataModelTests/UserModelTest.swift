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
    var owner: UInt?
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
        let superUser = User(id: 2, isSuperUser: true, username: "superuser", groups: [])

        // Test superuser always has permission
        var dummyResource = Dummy(owner: nil, permissions: nil)
        #expect(superUser.canChange(dummyResource))
        // Resource without owner is accessible to all
        #expect(user.canChange(dummyResource))

        // Test resource without owner is accessible to all
        dummyResource = Dummy(owner: nil, permissions: Permissions(view: .init(), change: .init()))
        #expect(superUser.canChange(dummyResource))
        #expect(user.canChange(dummyResource))

        // Test user with direct permission
        dummyResource = Dummy(owner: 5, permissions: Permissions(view: .init(), change: .init(users: [1], groups: [])))
        #expect(user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))

        // Test user is owner of resource
        dummyResource = Dummy(owner: 1, permissions: Permissions(view: .init(), change: .init()))
        #expect(user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))

        // Test user in group with permission
        dummyResource = Dummy(owner: 5, permissions: Permissions(view: .init(), change: .init(users: [], groups: [2])))
        #expect(user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))

        // Test another user has explicit permission
        dummyResource = Dummy(owner: 5, permissions: Permissions(view: .init(), change: .init(users: [7], groups: [])))
        #expect(!user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))

        // Test another group has permission
        dummyResource = Dummy(owner: 5, permissions: Permissions(view: .init(), change: .init(users: [], groups: [7])))
        #expect(!user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))

        // Test user without any permissions
        dummyResource = Dummy(owner: 5, permissions: Permissions(view: .init(), change: .init(users: [], groups: [])))
        #expect(!user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))

        // Test nil permissions returns false for normal user but true for superuser
        dummyResource = Dummy(owner: 5, permissions: nil)
        #expect(!user.canChange(dummyResource))
        #expect(superUser.canChange(dummyResource))
    }
}
