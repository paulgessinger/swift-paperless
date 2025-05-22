//
//  DateOnlyCoderTest.swift
//  Common
//
//  Created by Paul Gessinger on 22.05.25.
//

@testable import Common
import Foundation
import MetaCodable
import Testing

@Codable
@MemberInit
struct TestStruct {
    @CodedBy(DateOnlyCoder())
    var created: Date
}

@Test("Date only coder")
func testDateOnlyCoder() throws {
    let d = try #require(Calendar.current.date(from: DateComponents(year: 2023, month: 12, day: 4, hour: 9, minute: 10, second: 24)))
    let o = TestStruct(created: d)

    let encoder = JSONEncoder()

    let encoded = try encoder.encode(o)
    let s = String(data: encoded, encoding: .utf8)!
    #expect(s == #"{"created":"2023-12-04"}"#)
}

@Test("Sanity check: can decode any date")
func testDateOnlyCoderDecode() throws {
    let dateOnly = try #require(#"{"created":"2023-12-04"}"#.data(using: .utf8))

    let decoder = JSONDecoder()

    var decoded = try decoder.decode(TestStruct.self, from: dateOnly)

    let exp = try #require(Calendar.current.date(from: DateComponents(year: 2023, month: 12, day: 4, hour: 0, minute: 0, second: 0)))
    #expect(decoded.created == exp)

    let tz = TimeZone(secondsFromGMT: 60 * 60)!
    let dateTime = try #require(#"{"created":"2023-12-04T09:10:24+01:00"}"#.data(using: .utf8))

    decoded = try decoder.decode(TestStruct.self, from: dateTime)

    var cal = Calendar.current
    cal.timeZone = tz
    let components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: decoded.created)

    #expect(components.year == 2023)
    #expect(components.month == 12)
    #expect(components.day == 4)
    #expect(components.hour == 9)
    #expect(components.minute == 10)
    #expect(components.second == 24)
}
