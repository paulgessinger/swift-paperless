//
//  DocumentTypeTest.swift
//  DataModel
//
//  Created by Paul Gessinger on 03.01.25.
//

import Common
@testable import DataModel
import Testing

@Suite
struct DocumentTypeTest {
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

        let documentType = try makeDecoder(tz: .current).decode(DocumentType.self, from: data)

        #expect(documentType.id == 11)
        #expect(documentType.slug == "form")
        #expect(documentType.name == "Form")
        #expect(documentType.match == "Word")
        #expect(documentType.matchingAlgorithm == .any)
        #expect(documentType.isInsensitive == true)
    }
}
