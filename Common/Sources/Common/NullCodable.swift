//
//  NullCodable.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.08.23.
//

import Foundation

@propertyWrapper
public struct NullCodable<T> {
    public var wrappedValue: T?

    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }
}

extension NullCodable: Sendable where T: Sendable {}

extension NullCodable: Encodable where T: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch wrappedValue {
        case .none:
            try container.encodeNil()
        case let .some(value):
            try container.encode(value)
        }
    }
}

extension NullCodable: Decodable where T: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if !container.decodeNil() {
            wrappedValue = try container.decode(T.self)
        }
    }
}

extension NullCodable: Equatable where T: Equatable {}
extension NullCodable: Hashable where T: Hashable {}
