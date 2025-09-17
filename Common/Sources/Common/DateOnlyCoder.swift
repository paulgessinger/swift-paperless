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

    let ex = /(\d{4}-\d{2}-\d{2}).*/

    guard let match = try? ex.wholeMatch(in: dateStr) else {
      throw DateDecodingError.invalidDate(string: dateStr)
    }

    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"

    guard let res = df.date(from: String(match.1)) else {
      throw DateDecodingError.invalidDate(string: dateStr)
    }

    return res
  }

  public func encode(_ value: Coded, to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    try container.encode(formatter.string(from: value))
  }
}
