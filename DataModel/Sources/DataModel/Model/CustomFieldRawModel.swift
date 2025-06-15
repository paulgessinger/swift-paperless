//
//  CustomFieldRawModel.swift
//  DataModel
//
//  Created by AI Assistant on 26.03.2024.
//

import Foundation

public struct CustomFieldUnknownValue: Error {
    var debugDescription: String {
        "Unknown value type, cannot encode because this can lead to data loss"
    }
}

public enum CustomFieldRawValue: Codable, Sendable, Equatable, Hashable {
    case string(String)
    case float(Double)
    case integer(Int)
    case boolean(Bool)
    case idList([UInt])
    case none
    case unknown

    public static func == (lhs: CustomFieldRawValue, rhs: CustomFieldRawValue) -> Bool {
        switch (lhs, rhs) {
        case let (.string(lhs), .string(rhs)):
            lhs == rhs
        case let (.float(lhs), .float(rhs)):
            lhs == rhs
        case let (.integer(lhs), .integer(rhs)):
            lhs == rhs
        case let (.boolean(lhs), .boolean(rhs)):
            lhs == rhs
        case let (.idList(lhs), .idList(rhs)):
            lhs == rhs
        case (.none, .none):
            true
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
            self = .float(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode([UInt].self) {
            self = .idList(value)
        } else if container.decodeNil() {
            self = .none
        } else {
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .float(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        case let .idList(value):
            try container.encode(value)
        case .none:
            try container.encodeNil()
        case .unknown:
            throw CustomFieldUnknownValue()
        }
    }
}

public struct CustomFieldRawEntryList: Codable, Sendable, Equatable, Hashable {
    public var values: [CustomFieldRawEntry] = []
    public var hasUnknown: Bool {
        values.contains { $0.value == .unknown }
    }

    public init() {}

    public init(_ values: [CustomFieldRawEntry]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = try container.decode([CustomFieldRawEntry].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    public var count: Int {
        values.count
    }

    public subscript(_ index: Int) -> CustomFieldRawEntry {
        values[index]
    }
}

public struct CustomFieldRawEntry: Codable, Sendable, Equatable, Hashable {
    public var field: UInt
    public var value: CustomFieldRawValue
}
