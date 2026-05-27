//
//  ApiUserTest.swift
//  Networking
//

import Common
import DataModel
import Foundation
import Testing

@testable import Networking

private let tz = TimeZone(secondsFromGMT: 60 * 60)!
private let decoder = makeDecoder(tz: tz)

@Suite
struct ApiUserTest {
  @Test func testUserDecoding() throws {
    let data = try #require(testData("Data/users.json"))
    let users = try decoder.decode([ApiUser].self, from: data).map(\.domain)

    #expect(users[0].id == 42)
    #expect(users[0].username == "testuser123")
    #expect(users[0].isSuperUser == false)
    #expect(users[0].groups == [1, 3, 5])

    #expect(users[1].id == 77)
    #expect(users[1].username == "admin")
    #expect(users[1].isSuperUser == true)
    #expect(users[1].groups == [1])
  }

  @Test func testUserGroupDecoding() throws {
    let jsonData = """
      {
          "id": 7,
          "name": "Administrators"
      }
      """.data(using: .utf8)!

    let group = try decoder.decode(ApiUserGroup.self, from: jsonData).domain

    #expect(group.id == 7)
    #expect(group.name == "Administrators")
  }

  @Test func testUserPermissionsDecoding() throws {
    let jsonData = """
      ["view_document", "change_document", "add_tag"]
      """.data(using: .utf8)!

    let permissions = try decoder.decode(ApiUserPermissions.self, from: jsonData).domain

    #expect(permissions.test(.view, for: .document))
    #expect(permissions.test(.change, for: .document))
    #expect(permissions.test(.add, for: .tag))
    #expect(!permissions.test(.delete, for: .document))
    #expect(!permissions.test(.view, for: .tag))
  }

  @Test func testUserPermissionsFullMatrix() throws {
    let data = try #require(testData("Data/permissions.json"))

    struct Response: Decodable {
      var permissions: ApiUserPermissions
    }

    let permissions = try decoder.decode(Response.self, from: data).permissions.domain

    // Spot-check across resources / operations
    #expect(permissions.test(.add, for: .document))
    #expect(permissions.test(.delete, for: .documentType))
    #expect(permissions.test(.view, for: .storagePath))
    #expect(permissions.test(.change, for: .user))
    #expect(permissions.test(.view, for: .mailRule))
    #expect(permissions.test(.delete, for: .workflow))
    #expect(permissions.test(.add, for: .customField))
    #expect(permissions.test(.view, for: .savedView))
  }

  @Test func testUserPermissionsEncoding() throws {
    var permissions = UserPermissions(rules: [:])
    permissions.set(.add, to: true, for: .document)
    permissions.set(.view, to: true, for: .document)
    permissions.set(.change, to: true, for: .user)

    let wire = ApiUserPermissions(from: permissions)
    let encodedData = try JSONEncoder().encode(wire)

    let expectedOutputSet: Set<String> = ["add_document", "view_document", "change_user"]
    let decodedArray = try JSONDecoder().decode([String].self, from: encodedData)
    let encodedStringSet = Set(decodedArray)
    #expect(encodedStringSet == expectedOutputSet)
  }

  @Test func testUserPermissionsRoundTrip() throws {
    let permissions = UserPermissions.empty { p in
      p.set(.view, to: true, for: .document)
      p.set(.change, to: true, for: .document)
      p.set(.add, to: true, for: .tag)
    }

    let wire = ApiUserPermissions(from: permissions)
    let encoded = try JSONEncoder().encode(wire)
    let decoded = try JSONDecoder().decode(ApiUserPermissions.self, from: encoded).domain

    #expect(decoded.test(.view, for: .document))
    #expect(decoded.test(.change, for: .document))
    #expect(decoded.test(.add, for: .tag))
    #expect(!decoded.test(.delete, for: .document))
  }
}
