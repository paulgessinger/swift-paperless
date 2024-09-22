//
//  EquatableNoop.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.09.2024.
//

@propertyWrapper
struct EquatableNoop<Value>: Equatable {
    var wrappedValue: Value

    static func == (_: EquatableNoop<Value>, _: EquatableNoop<Value>) -> Bool {
        true
    }
}

extension EquatableNoop: Sendable where Value: Sendable {}

extension EquatableNoop: Codable where Value: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode(Value.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}
