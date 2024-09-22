//
//  DecodeOnly.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 24.07.2024.
//

import Foundation

@propertyWrapper
public struct DecodeOnly<T: Decodable> {
    public var wrappedValue: T

    public init(wrappedValue defaultValue: T) {
        wrappedValue = defaultValue
    }
}

// Always conform to encodable, because we never actually encode anything
extension DecodeOnly: Encodable {
    public func encode(to _: any Encoder) throws {
        // Intentionally empty
    }
}

extension DecodeOnly: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode(T.self)
    }
}

extension DecodeOnly: Equatable where T: Equatable {}
extension DecodeOnly: Hashable where T: Hashable {}
extension DecodeOnly: Sendable where T: Sendable {}

// This avoids generating the output key at all
public extension KeyedEncodingContainer {
    mutating func encode(
        _: DecodeOnly<some Any>,
        forKey _: KeyedEncodingContainer<K>.Key
    ) throws {
        // Do nothing
    }
}

// If the wrapped type is an optional, the key is optional
public extension KeyedDecodingContainer {
    func decode<V: ExpressibleByNilLiteral>(_ t: DecodeOnly<V>.Type, forKey key: K) throws -> DecodeOnly<V> {
        if let v = try decodeIfPresent(t, forKey: key) {
            return v
        }
        return DecodeOnly<V>(wrappedValue: nil)
    }
}
