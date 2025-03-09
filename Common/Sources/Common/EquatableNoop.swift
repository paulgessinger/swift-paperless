//
//  EquatableNoop.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.09.2024.
//

@propertyWrapper
public
struct EquatableNoop<Value>: Equatable {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    public static func == (_: EquatableNoop<Value>, _: EquatableNoop<Value>) -> Bool {
        true
    }
}

extension EquatableNoop: Sendable where Value: Sendable {}

extension EquatableNoop: Codable where Value: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode(Value.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}
