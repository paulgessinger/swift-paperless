//
//  DateOnlyCoder.swift
//  Common
//
//  Created by Paul Gessinger on 22.05.25.
//

import Foundation
import MetaCodable
import os

public struct DateOnlyCoder: HelperCoder {
  public typealias Coded = Date

  public init() {}

  public func decode(from decoder: Decoder) throws -> Coded {
    let container = try decoder.singleValueContainer()
    let dateStr = try container.decode(String.self)

    let ex = /(\d{4})-(\d{2})-(\d{2}).*/

    guard let match = try? ex.wholeMatch(in: dateStr) else {
      Logger.common.error(
        "DateOnlyCoder: date \(dateStr, privacy: .public) does not match expected format YYYY-MM-DD"
      )
      throw DateDecodingError.invalidDate(string: dateStr)
    }

    // Extract year, month, day from regex capture groups
    if let year = Int(match.1),
      let month = Int(match.2),
      let day = Int(match.3)
    {

      // Build date from components using Gregorian calendar with current timezone
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone.current

      let components = DateComponents(
        year: year, month: month, day: day, hour: 0, minute: 0, second: 0)

      if let res = calendar.date(from: components) {
        return res
      }

      Logger.common.warning(
        "DateOnlyCoder: failed to create date from components for \(dateStr, privacy: .public), falling back to DateFormatter"
      )
    } else {
      Logger.common.warning(
        "DateOnlyCoder: failed to parse numeric components from \(dateStr, privacy: .public), falling back to DateFormatter"
      )
    }

    // Fallback to DateFormatter with en_US_POSIX locale
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    df.locale = Locale(identifier: "en_US_POSIX")

    guard let res = df.date(from: String(match.1)) else {
      Logger.common.error(
        "DateOnlyCoder: date \(dateStr, privacy: .public) could not be parsed even with fallback DateFormatter"
      )
      throw DateDecodingError.invalidDate(string: dateStr)
    }

    return res
  }

  public func encode(_ value: Coded, to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")

    try container.encode(formatter.string(from: value))
  }
}
