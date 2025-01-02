//
//  DateDecoderTest.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 18.05.2024.
//

import Common
import Foundation
import Testing

let tz = TimeZone(secondsFromGMT: 60 * 60)!

@Suite
struct DateDecoderTest {
    @Test
    func testISO8691Zulu() throws {
        let input = "\"2024-05-13T23:38:10.546679Z\"".data(using: .utf8)!
        let date = try makeDecoder(tz: .current).decode(Date.self, from: input)
        var cal = Calendar.current
        cal.timeZone = tz
        let components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(components.year == 2024)
        #expect(components.month == 5)
        #expect(components.day == 14)
        #expect(components.hour == 0)
        #expect(components.minute == 38)
        #expect(components.second == 10)
    }

    @Test
    func testMidnightTimeZone() throws {
        let input = "\"2024-12-21T00:00:00+01:00\"".data(using: .utf8)!
        let date = try makeDecoder(tz: tz).decode(Date.self, from: input)
        print(tz.secondsFromGMT())

        var cal = Calendar.current
        cal.timeZone = tz

        let components = cal.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(components.year == 2024)
        #expect(components.month == 12)
        #expect(components.day == 21)
        #expect(components.hour == 0)
    }
}
