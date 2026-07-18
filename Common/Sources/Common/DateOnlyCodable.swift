//
//  DateOnlyCodable.swift
//  Common
//
//  Created by Paul Gessinger on 22.05.25.
//

import Foundation
import os

/// A property wrapper that encodes and decodes ``Date`` values as `YYYY-MM-DD` strings.
///
/// The date is always interpreted in the local timezone, stripping any time-of-day
/// or timezone offset that may appear in the raw string (Paperless-ngx sometimes
/// returns a full ISO-8601 timestamp even for date-only fields).
///
/// ```swift
/// struct MyModel: Codable {
///     @DateOnlyCodable var created: Date
/// }
/// // Decodes {"created":"2023-12-04"} → midnight on 2023-12-04 in the local timezone.
/// // Also handles {"created":"2023-12-04T09:10:24+01:00"} identically.
/// ```
@propertyWrapper
public struct DateOnlyCodable: Codable, Hashable, Sendable {
  public var wrappedValue: Date

  public init(wrappedValue: Date) {
    self.wrappedValue = wrappedValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let dateStr = try container.decode(String.self)

    let ex = /(\d{4})-(\d{2})-(\d{2}).*/

    guard let match = try? ex.wholeMatch(in: dateStr) else {
      Logger.common.error(
        "DateOnlyCodable: date \(dateStr, privacy: .public) does not match expected format YYYY-MM-DD"
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
        self.wrappedValue = res
        return
      }

      Logger.common.warning(
        "DateOnlyCodable: failed to create date from components for \(dateStr, privacy: .public), falling back to DateFormatter"
      )
    } else {
      Logger.common.warning(
        "DateOnlyCodable: failed to parse numeric components from \(dateStr, privacy: .public), falling back to DateFormatter"
      )
    }

    // Fallback to DateFormatter with en_US_POSIX locale
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    df.locale = Locale(identifier: "en_US_POSIX")

    let dateOnly = "\(match.1)-\(match.2)-\(match.3)"
    guard let res = df.date(from: dateOnly) else {
      Logger.common.error(
        "DateOnlyCodable: date \(dateStr, privacy: .public) could not be parsed even with fallback DateFormatter"
      )
      throw DateDecodingError.invalidDate(string: dateStr)
    }

    self.wrappedValue = res
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")

    try container.encode(formatter.string(from: wrappedValue))
  }
}
