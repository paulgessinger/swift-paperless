//
//  DateDecoderTest.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 18.05.2024.
//

import XCTest

final class DateDecoderTest: XCTestCase {
    func testISO8691() throws {
        let input = "\"2024-05-13T23:38:10.546679Z\"".data(using: .utf8)!
        let result = try makeDecoder(tz: .current).decode(Date.self, from: input)
    }

    func testDates() throws {
        let input = "\"2023-02-25T10:13:54.057805+01:00\"".data(using: .utf8)!
        let date = try decoder.decode(Date.self, from: input)
        XCTAssertNotNil(date)

        let input2 = "\"2023-02-18T00:00:00+01:00\"".data(using: .utf8)!
        let date2 = try decoder.decode(Date.self, from: input2)
        XCTAssertNotNil(date2)
    }
}
