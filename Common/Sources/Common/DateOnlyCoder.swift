//
//  DateOnlyCoder.swift
//  Common
//
//  Created by Paul Gessinger on 22.05.25.
//

import Foundation
import MetaCodable

public struct DateOnlyCoder: HelperCoder {
    public typealias Coded = Date

    public init() {}

    public func decode(from decoder: Decoder) throws -> Coded {
        let container = try decoder.singleValueContainer()
        let dateStr = try container.decode(String.self)

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        if let res = df.date(from: dateStr) {
            return res
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let res = iso.date(from: dateStr) {
            return res
        }

        iso.formatOptions = [.withInternetDateTime]
        if let res = iso.date(from: dateStr) {
            return res
        }

        throw DateDecodingError.invalidDate(string: dateStr)
    }

    public func encode(_ value: Coded, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        try container.encode(formatter.string(from: value))
    }
}
