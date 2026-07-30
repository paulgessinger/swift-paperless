//
//  ApiDocumentTypeTest.swift
//  Networking
//

import Common
import DataModel
import Testing

@testable import Networking

@Suite
struct ApiDocumentTypeTest {
  @Test func testDecoding() throws {
    let data = """
      {
          "id": 11,
          "slug": "form",
          "name": "Form",
          "match": "Word",
          "matching_algorithm": 1,
          "is_insensitive": true,
          "document_count": 21,
          "owner": 2,
          "user_can_change": true
      }
      """.data(using: .utf8)!

    let documentType = try makeDecoder(tz: .current).decode(
      ApiDocumentType.self, from: data
    ).domain

    #expect(documentType.id == 11)
    #expect(documentType.slug == "form")
    #expect(documentType.name == "Form")
    #expect(documentType.match == "Word")
    #expect(documentType.matchingAlgorithm == .any)
    #expect(documentType.isInsensitive == true)
  }
}
