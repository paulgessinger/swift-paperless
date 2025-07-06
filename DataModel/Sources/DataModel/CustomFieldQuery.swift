import CasePaths
import Foundation
import os

public struct OpContent: Sendable, Equatable, Hashable {
    public var op: CustomFieldQuery.LogicalOperator
    public var args: [CustomFieldQuery]

    public init(op: CustomFieldQuery.LogicalOperator, args: [CustomFieldQuery]) {
        self.op = op
        self.args = args
    }
}

public struct ExprContent: Sendable, Equatable, Hashable {
    public var id: UInt
    public var op: CustomFieldQuery.FieldOperator
    public var arg: CustomFieldQuery.Argument

    public init(id: UInt, op: CustomFieldQuery.FieldOperator, arg: CustomFieldQuery.Argument) {
        self.id = id
        self.op = op
        self.arg = arg
    }
}

@CasePathable
@dynamicMemberLookup
public indirect enum CustomFieldQuery: Equatable, Sendable, Hashable {
    public enum LogicalOperator: String, Codable, Sendable, Hashable {
        case or = "OR"
        case and = "AND"
    }

    public enum FieldOperator: String, Codable, Sendable, Hashable {
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

    public enum Argument: Equatable, Sendable, Hashable {
        case string(String)
        case number(Double)
        case integer(Int)
        indirect case array([Argument])
    }

    public static func op(_ op: LogicalOperator, _ args: [CustomFieldQuery]) -> CustomFieldQuery {
        .op(OpContent(op: op, args: args))
    }

    public static func expr(_ id: UInt, _ op: FieldOperator, _ arg: Argument) -> CustomFieldQuery {
        .expr(ExprContent(id: id, op: op, arg: arg))
    }

    case op(OpContent)
    case expr(ExprContent)
    case any
}

extension CustomFieldQuery: Codable {
    public init(from decoder: Decoder) throws {
        // Check if the JSON is null
        if let container = try? decoder.singleValueContainer(), container.decodeNil() {
            self = .any
            return
        }

        // Otherwise decode as an array
        var container = try decoder.unkeyedContainer()

        // @TODO: Maybe push this to decoder of the content structs?
        if container.count == 2 {
            let op = try container.decode(LogicalOperator.self)
            let args = try container.decode([CustomFieldQuery].self)

            self = .op(OpContent(op: op, args: args))
        } else if container.count == 3 {
            let id = try container.decode(UInt.self)
            let op = try container.decode(FieldOperator.self)
            let arg = try container.decode(Argument.self)

            self = .expr(ExprContent(id: id, op: op, arg: arg))
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected 2 or 3 elements in array"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        // @TODO: Maybe push this to encoder of the content structs?
        switch self {
        case let .op(opContent):
            var container = encoder.unkeyedContainer()
            try container.encode(opContent.op)
            try container.encode(opContent.args)
        case let .expr(exprContent):
            var container = encoder.unkeyedContainer()
            try container.encode(exprContent.id)
            try container.encode(exprContent.op)
            try container.encode(exprContent.arg)
        case .any:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
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
