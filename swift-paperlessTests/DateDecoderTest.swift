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
}
