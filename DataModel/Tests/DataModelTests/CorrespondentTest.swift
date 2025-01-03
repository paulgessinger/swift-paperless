//
//  CorrespondentTest.swift
//  DataModel
//
//  Created by Paul Gessinger on 03.01.25.
//

import Common
@testable import DataModel
import Testing

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
//        #expect(correspondent.owner == 2)
//        #expect(correspondent.userCanChange == true)
    }
}
