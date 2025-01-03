//
//  SuggestionsTest.swift
//  DataModel
//
//  Created by Assistant on 03.01.25.
//

import Common
@testable import DataModel
import Testing

@Suite
struct SuggestionsTest {
    @Test func testDecoding() throws {
        let data = try #require(testData("Data/suggestions.json"))

        let suggestions = try makeDecoder(tz: .current).decode(Suggestions.self, from: data)

        #expect(suggestions.correspondents == [72])
        #expect(suggestions.tags == [9])
        #expect(suggestions.documentTypes == [4])
        #expect(suggestions.storagePaths.isEmpty)
        #expect(dateApprox(suggestions.dates[0], datetime(year: 2024, month: 12, day: 3, hour: 0, minute: 0, second: 0, tz: .current)))
        #expect(dateApprox(suggestions.dates[1], datetime(year: 2025, month: 1, day: 2, hour: 0, minute: 0, second: 0, tz: .current)))
    }
}
