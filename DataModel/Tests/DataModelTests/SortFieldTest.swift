//
//  SortFieldTest.swift
//  DataModel
//
//  Created by Paul Gessinger on 03.01.25.
//

import Common
@testable import DataModel
import Foundation
import Testing

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

    @Test("Tests that invalid values throw decoding errors", arguments: [
        "invalid_sort_field",
        "unknown",
        "test",
    ])
    func testInvalidDecoding(invalidValue: String) throws {
        let invalidJson = """
        "\(invalidValue)"
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(SortField.self, from: invalidJson)
        }
    }
}
