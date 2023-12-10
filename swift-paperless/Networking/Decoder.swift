//
//  Decoder.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 10.12.2023.
//

import Foundation

let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { decoder -> Date in
        let container = try decoder.singleValueContainer()
        let dateStr = try container.decode(String.self)

        let iso = ISO8601DateFormatter()
        if let res = iso.date(from: dateStr) {
            return res
        }

        let df = DateFormatter()
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSZZZZZ"

        if let res = df.date(from: dateStr) {
            return res
        }

        df.dateFormat = "yyyy-MM-dd"

        if let res = df.date(from: dateStr) {
            return res
        }

        throw DateDecodingError.invalidDate(string: dateStr)
    }
//    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}()
