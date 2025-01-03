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

@Suite
struct UserModelTest {
    @Test func testDecoding() throws {
        let data = try #require(testData("Data/users.json"))
        let users = try decoder.decode([User].self, from: data)

        // Test regular user
        #expect(users[0].id == 42)
        #expect(users[0].username == "testuser123")
        #expect(users[0].isSuperUser == false)

        // Test admin user
        #expect(users[1].id == 77)
        #expect(users[1].username == "admin")
        #expect(users[1].isSuperUser == true)
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
}
