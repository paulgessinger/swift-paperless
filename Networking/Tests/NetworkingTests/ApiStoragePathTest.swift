//
//  ApiStoragePathTest.swift
//  Networking
//

import Common
import DataModel
import Testing

@testable import Networking

@Suite
struct ApiStoragePathTest {
  @Test func testDecoding() throws {
    let data = """
      {
          "id": 1,
          "slug": "haushalt",
          "name": "Haushalt",
          "path": "Haushalt/{{ created_year }}/{{ document_type }}_{{ title }}__{{ tag_list }}",
          "match": "",
          "matching_algorithm": 6,
          "is_insensitive": true,
          "document_count": 76,
          "owner": 2,
          "user_can_change": true
      }
      """.data(using: .utf8)!

    let storagePath = try makeDecoder(tz: .current).decode(
      ApiStoragePath.self, from: data
    ).domain

    #expect(storagePath.id == 1)
    #expect(storagePath.slug == "haushalt")
    #expect(storagePath.name == "Haushalt")
    #expect(
      storagePath.path
        == "Haushalt/{{ created_year }}/{{ document_type }}_{{ title }}__{{ tag_list }}")
    #expect(storagePath.match == "")
    #expect(storagePath.matchingAlgorithm == .auto)
    #expect(storagePath.isInsensitive == true)
  }
}
