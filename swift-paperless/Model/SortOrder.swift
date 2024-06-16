//
//  SortOrder.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.06.2024.
//

import Foundation

enum SortOrder: Codable {
    case ascending
    case descending

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let reverse = try container.decode(Bool.self)
        self.init(reverse)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(reverse)
    }

    var localizedName: String {
        switch self {
        case .ascending:
            return String(localized: .localizable(.ascending))
        case .descending:
            return String(localized: .localizable(.descending))
        }
    }

    var reverse: Bool {
        switch self {
        case .descending:
            return true
        case .ascending:
            return false
        }
    }

    init(_ reverse: Bool) {
        if reverse {
            self = .descending
        } else {
            self = .ascending
        }
    }
}
