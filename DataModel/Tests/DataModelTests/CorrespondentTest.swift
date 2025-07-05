//
//  CorrespondentTest.swift
//  DataModel
//
//  Created by Paul Gessinger on 03.01.25.
//

import Common
import Foundation
import Testing

@testable import DataModel

@Suite
struct CorrespondentTest {
  @Test func testDecoding() throws {
    let data = """
      {
          "id": 88,
          "slug": "aaaaaa",
          "name": "Aaaaaa",
          "match": "",
          "matching_algorithm": 6,
          "is_insensitive": false,
          "document_count": 0,
          "last_correspondence": null,
          "owner": 2,
          "user_can_change": true
      }
      """.data(using: .utf8)!

    let correspondent = try makeDecoder(tz: .current).decode(Correspondent.self, from: data)

    #expect(correspondent.id == 88)
    #expect(correspondent.slug == "aaaaaa")
    #expect(correspondent.name == "Aaaaaa")
    #expect(correspondent.match == "")
    #expect(correspondent.matchingAlgorithm == .auto)
    #expect(correspondent.isInsensitive == false)
    #expect(correspondent.documentCount == 0)
    #expect(correspondent.lastCorrespondence == nil)
  }

  @Test func testEncoding() throws {
    let correspondent = Correspondent(
      id: 88, documentCount: 0, lastCorrespondence: nil, name: "Aaaaaa", slug: "aaaaaa",
      matchingAlgorithm: .auto, match: "", isInsensitive: false)

    let encoder = JSONEncoder()

    let data = try encoder.encode(correspondent)

    struct Decoded: Decodable {
      let id: Int
      let slug: String
      let name: String
      let match: String
      let matching_algorithm: Int
    }

    let decoded = try JSONDecoder().decode(Decoded.self, from: data)

    #expect(decoded.id == 88)
    #expect(decoded.slug == "aaaaaa")
    #expect(decoded.name == "Aaaaaa")
    #expect(decoded.match == "")
    #expect(decoded.matching_algorithm == 6)
  }

  @Test("Test proto correspondent encoding without explicit permissions")
  func testProtoCorrespondent() throws {
    let correspondent = ProtoCorrespondent(
      name: "Aaaaaa", matchingAlgorithm: .auto, match: "", isInsensitive: false)

    let data = try JSONEncoder().encode(correspondent)

    struct Decoded: Decodable {
      let name: String
      let matching_algorithm: Int
      let match: String
      let is_insensitive: Bool
    }

    let decoded = try JSONDecoder().decode(Decoded.self, from: data)

    #expect(decoded.name == "Aaaaaa")
    #expect(decoded.matching_algorithm == 6)
    #expect(decoded.match == "")
    #expect(decoded.is_insensitive == false)
  }

  @Test("Test proto correspondent encoding with explicit permissions")
  func testProtoCorrespondentWithPermissions() throws {
    let perms = Permissions {
      $0.view.users = [2]
      $0.change.users = [2]
      $0.view.groups = [1]
      $0.change.groups = [1]
    }

    var correspondent = ProtoCorrespondent(
      name: "Aaaaaa", matchingAlgorithm: .auto, match: "", isInsensitive: false, owner: .user(2))
    correspondent.permissions = perms  // needed to trigger the didSet

    let data = try JSONEncoder().encode(correspondent)

    struct DecodedPermissions: Decodable {
      let view: [String: [Int]]
      let change: [String: [Int]]
    }

    struct Decoded: Decodable {
      let name: String
      let matching_algorithm: Int
      let match: String
      let is_insensitive: Bool
      let owner: Int
      let set_permissions: DecodedPermissions?
    }

    let decoded = try JSONDecoder().decode(Decoded.self, from: data)

    #expect(decoded.name == "Aaaaaa")
    #expect(decoded.owner == 2)
    #expect(decoded.set_permissions?.view["users"] == [2])
    #expect(decoded.set_permissions?.change["users"] == [2])
    #expect(decoded.set_permissions?.view["groups"] == [1])
    #expect(decoded.set_permissions?.change["groups"] == [1])
    #expect(decoded.matching_algorithm == 6)
    #expect(decoded.is_insensitive == false)
  }
}
