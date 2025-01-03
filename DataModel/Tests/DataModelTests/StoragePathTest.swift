//
//  StoragePathTest.swift
//  DataModel
//
//  Created by AI on 14.03.24.
//

import Common
@testable import DataModel
import Testing

@Suite
struct StoragePathTest {
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

        let storagePath = try makeDecoder(tz: .current).decode(StoragePath.self, from: data)

        #expect(storagePath.id == 1)
        #expect(storagePath.slug == "haushalt")
        #expect(storagePath.name == "Haushalt")
        #expect(storagePath.path == "Haushalt/{{ created_year }}/{{ document_type }}_{{ title }}__{{ tag_list }}")
        #expect(storagePath.match == "")
        #expect(storagePath.matchingAlgorithm == .auto)
        #expect(storagePath.isInsensitive == true)
    }
}
