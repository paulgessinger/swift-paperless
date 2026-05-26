//
//  DateOnlyCoderTest.swift
//  Common
//
//  Created by Paul Gessinger on 22.05.25.
//

import Foundation
import MetaCodable
import Testing

@testable import Common

@Codable
@MemberInit
struct TestStruct {
  @CodedBy(DateOnlyCoder())
  var created: Date
}

@Suite("DateOnlyCoder Tests")
struct DateOnlyCoderTestSuite {

  @Test("Date only coder")
  func testDateOnlyCoder() throws {
    let d = try #require(
      Calendar.current.date(
        from: DateComponents(year: 2023, month: 12, day: 4, hour: 9, minute: 10, second: 24)))
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
    print(decoded)

    // Expect date in current timezone
    let exp = try #require(
      Calendar.current.date(
        from: DateComponents(year: 2023, month: 12, day: 4, hour: 0, minute: 0, second: 0)))
    #expect(decoded.created == exp)

    let dateTime = try #require(#"{"created":"2023-12-04T09:10:24+01:00"}"#.data(using: .utf8))

    decoded = try decoder.decode(TestStruct.self, from: dateTime)

    // Check components in current timezone
    let cal = Calendar.current
    let components = cal.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: decoded.created)

    #expect(components.year == 2023)
    #expect(components.month == 12)
    #expect(components.day == 4)
    #expect(components.hour == 0)
    #expect(components.minute == 0)
    #expect(components.second == 0)
  }

  @Test("Arbitrary timezones get stripped out", arguments: 1...10)
  func testArbitraryTimezonesGetStrippedOut(offset: Int) throws {
    let dateOnly = try #require(
      "{\"created\":\"2028-11-02T00:00:00+0\(offset):00\"}".data(using: .utf8))

    let decoder = JSONDecoder()

    let decoded = try decoder.decode(TestStruct.self, from: dateOnly)

    // Check components in current timezone
    let cal = Calendar.current
    let components = cal.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: decoded.created)

    #expect(components.year == 2028)
    #expect(components.month == 11)
    #expect(components.day == 2)
    #expect(components.hour == 0)
    #expect(components.minute == 0)
    #expect(components.second == 0)
  }

  @Test("DateFormatter without explicit locale can fail")
  func testDateFormatterLocaleIssue() throws {
    let dateString = "1990-10-21"

    // Test various locales to see which ones fail
    let testLocales = [
      // Non-Gregorian calendars
      "th_TH",  // Thai - Buddhist calendar
      "ar_SA",  // Arabic (Saudi Arabia) - Hijri calendar
      "fa_IR",  // Persian (Iran) - Persian calendar
      "he_IL",  // Hebrew (Israel) - Hebrew calendar
      "ja_JP@calendar=japanese",  // Japanese - Japanese calendar
      "zh_TW@calendar=roc",  // Chinese (Taiwan) - Republic of China calendar
      "ar_EG",  // Arabic (Egypt) - Hijri calendar
      "ar_AE",  // Arabic (UAE) - Hijri calendar
      "ar_KW",  // Arabic (Kuwait) - Hijri calendar
      "fa_AF",  // Persian (Afghanistan) - Persian calendar

      // Gregorian calendars - European locales that users report issues with
      "de_DE",  // German (Germany)
      "fr_FR",  // French (France)
      "es_ES",  // Spanish (Spain)
      "it_IT",  // Italian (Italy)
      "nl_NL",  // Dutch (Netherlands)
      "pl_PL",  // Polish (Poland)
      "ru_RU",  // Russian (Russia)
      "pt_BR",  // Portuguese (Brazil)
      "en_GB",  // English (UK)
      "sv_SE",  // Swedish (Sweden)
    ]

    var failedLocales: [String] = []
    var succeededLocales: [String] = []

    for localeId in testLocales {
      let df = DateFormatter()
      df.dateFormat = "yyyy-MM-dd"
      df.locale = Locale(identifier: localeId)

      let result = df.date(from: dateString)

      if result == nil {
        failedLocales.append(localeId)
      } else {
        succeededLocales.append(localeId)
      }
    }

    print("Failed locales: \(failedLocales)")
    print("Succeeded locales: \(succeededLocales)")

    // Prove that en_US_POSIX always works
    let posixDf = DateFormatter()
    posixDf.dateFormat = "yyyy-MM-dd"
    posixDf.locale = Locale(identifier: "en_US_POSIX")

    #expect(posixDf.date(from: dateString) != nil)
  }

}
