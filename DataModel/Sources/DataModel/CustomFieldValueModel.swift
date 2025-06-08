//
//  CustomFieldValueModel.swift
//  DataModel
//
//  Created by AI Assistant on 26.03.2024.
//

import Foundation
import MetaCodable

public enum CustomFieldValueType: Codable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case date(Date)
    // @TODO: Select
    case documentLink([UInt])
    case url(URL)
    case integer(Int)
    case float(Float)
    case monetary(currency: String, amount: Decimal)
}

public struct CustomFieldUnknownValue: Error {
    var debugDescription: String {
        "Unknown value type, cannot encode because this can lead to data loss"
    }
}

public enum CustomFieldRawType: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case idList([UInt])
    case unknown

    public static func == (lhs: CustomFieldRawType, rhs: CustomFieldRawType) -> Bool {
        switch (lhs, rhs) {
        case let (.string(lhs), .string(rhs)):
            lhs == rhs
        case let (.number(lhs), .number(rhs)):
            lhs == rhs
        case let (.integer(lhs), .integer(rhs)):
            lhs == rhs
        case let (.boolean(lhs), .boolean(rhs)):
            lhs == rhs
        case let (.idList(lhs), .idList(rhs)):
            lhs == rhs
        case (.unknown, .unknown):
            true
        default:
            false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode([UInt].self) {
            self = .idList(value)
        } else {
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        case let .idList(value):
            try container.encode(value)
        case .unknown:
            throw CustomFieldUnknownValue()
        }
    }
}

public struct CustomFieldRawValueList: Codable, Sendable {
    public var values: [CustomFieldRawEntry]
    public var hasUnknown: Bool {
        values.contains { $0.value == .unknown }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = try container.decode([CustomFieldRawEntry].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

public struct CustomFieldRawEntry: Codable, Sendable {
    public var field: UInt
    public var value: CustomFieldRawType
}
