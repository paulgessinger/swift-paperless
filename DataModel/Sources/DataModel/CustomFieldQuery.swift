import Foundation
import os

public indirect enum CustomFieldQuery: Equatable, Sendable {
    public enum LogicalOperator: String, Codable, Sendable {
        case or = "OR"
        case and = "AND"
    }

    public enum FieldOperator: String, Codable, Sendable {
        case exists
        case isnull
        case exact
        case gt
        case gte
        case lt
        case lte
        case `in`
        case contains
    }

    public enum Argument: Equatable, Sendable {
        case string(String)
        case number(Double)
        case integer(Int)
        indirect case array([Argument])
    }

    case op(LogicalOperator, [Self])
    case expr(UInt, FieldOperator, Argument)
}

extension CustomFieldQuery: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        if container.count == 2 {
            let op = try container.decode(LogicalOperator.self)
            let args = try container.decode([CustomFieldQuery].self)

            self = .op(op, args)
        } else if container.count == 3 {
            let id = try container.decode(UInt.self)
            let op = try container.decode(FieldOperator.self)
            let arg = try container.decode(Argument.self)

            self = .expr(id, op, arg)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected 2 or 3 elements in array"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()

        switch self {
        case let .op(op, args):
            try container.encode(op)
            try container.encode(args)
        case let .expr(id, op, arg):
            try container.encode(id)
            try container.encode(op)
            try container.encode(arg)
        }
    }
}

extension CustomFieldQuery: RawRepresentable {
    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self) else {
            Logger.dataModel.error("Failed to encode CustomFieldQuery, this is a bug!")
            return ""
        }
        guard let string = String(data: data, encoding: .utf8) else {
            Logger.dataModel.error("Failed to encode CustomFieldQuery, this is a bug!")
            return ""
        }
        return string
    }

    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8) else {
            return nil
        }
        guard let query = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = query
    }
}

extension CustomFieldQuery.Argument: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let int = try? container.decode(Int.self) {
            self = .integer(int)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let array = try? container.decode([Self].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected string, number, int, or array of arguments"
            )
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
        case let .array(values):
            try container.encode(values)
        }
    }
}
