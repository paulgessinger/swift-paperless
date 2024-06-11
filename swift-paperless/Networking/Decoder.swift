//
//  Decoder.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 10.12.2023.
//

import Foundation
import os

func makeDecoder(tz: TimeZone) -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { decoder -> Date in
        let container = try decoder.singleValueContainer()
        let dateStr = try container.decode(String.self)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let res = iso.date(from: dateStr) {
            return res
        }

        iso.formatOptions = [.withInternetDateTime]
        if let res = iso.date(from: dateStr) {
            return res
        }

        let df = DateFormatter()
        df.timeZone = tz
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"

        if let res = df.date(from: dateStr) {
            return res
        }

        Logger.shared.error("Unable to decode date from string: \(dateStr, privacy: .public)")
        throw DateDecodingError.invalidDate(string: dateStr)
    }
//    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}

let decoder: JSONDecoder = makeDecoder(tz: .current)
