//
//  SortFieldTest.swift
//  DataModel
//
//  Created by Paul Gessinger on 03.01.25.
//

import Common
import Foundation
import Testing

@testable import DataModel

private let decoder = makeDecoder(tz: .current)

@Suite
struct SortFieldTest {
  struct DecodingCase {
    let rawValue: String
    let expected: SortField

    static let allCases: [DecodingCase] = [
      .init(rawValue: "archive_serial_number", expected: .asn),
      .init(rawValue: "correspondent__name", expected: .correspondent),
      .init(rawValue: "title", expected: .title),
      .init(rawValue: "document_type__name", expected: .documentType),
      .init(rawValue: "created", expected: .created),
      .init(rawValue: "added", expected: .added),
      .init(rawValue: "modified", expected: .modified),
      .init(rawValue: "storage_path__name", expected: .storagePath),
      .init(rawValue: "owner", expected: .owner),
      .init(rawValue: "notes", expected: .notes),
      .init(rawValue: "score", expected: .score),
      .init(rawValue: "page_count", expected: .pageCount),
      .init(rawValue: "invalid", expected: .other("invalid")),
    ]
  }

  @Test("Tests decoding of all sort field values", arguments: DecodingCase.allCases)
  func testDecoding(testCase: DecodingCase) throws {
    let jsonData = """
      "\(testCase.rawValue)"
      """.data(using: .utf8)!

    let decoded = try decoder.decode(SortField.self, from: jsonData)
    #expect(decoded == testCase.expected)
  }

  @Test("Tests encoding and decoding roundtrip", arguments: SortField.allCases)
  func testEncoding(field: SortField) throws {
    let encoded = try JSONEncoder().encode(field)
    let decoded = try decoder.decode(SortField.self, from: encoded)
    #expect(field == decoded)
  }

  @Test("Tests encoding and decoding roundtrip for other values")
  func testEncodingOther() throws {
    let field = SortField.other("custom_field")
    let encoded = try JSONEncoder().encode(field)
    let decoded = try decoder.decode(SortField.self, from: encoded)
    #expect(field == decoded)
  }

  @Test(
    "Tests that invalid values produce catch-all case",
    arguments: [
      "invalid_sort_field",
      "unknown",
      "test",
    ]
  )
  func testInvalidDecoding(invalidValue: String) throws {
    let invalidJson = """
      "\(invalidValue)"
      """.data(using: .utf8)!

    let field = try decoder.decode(SortField.self, from: invalidJson)
    #expect(field == .other(invalidValue))
  }

  @Test("Tests encoding and decoding of custom fields")
  func testEncodingCustomField() throws {
    let field = SortField.customField(123)
    let encoded = try JSONEncoder().encode(field)
    let json = String(data: encoded, encoding: .utf8)!
    #expect(
      json == """
        "custom_field_123"
        """)
    let decoded = try decoder.decode(SortField.self, from: encoded)
    #expect(field == decoded)
  }
}
