//
//  NullCodable.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.08.23.
//

import Foundation
import MetaCodable

/// A helper coder that handles optional values that may be encoded as `null` in JSON.
/// This is useful when working with APIs that represent optional values as explicit `null`
/// rather than omitting the field entirely.
public struct NullCoder<T>: HelperCoder where T: Codable {
    public init() {}

    public func decode(from decoder: any Decoder) throws -> T {
        let container = try decoder.singleValueContainer()
        return try container.decode(T.self)
    }

    public func encodeIfPresent<EncodingContainer>(_ value: T?, to container: inout EncodingContainer, atKey key: EncodingContainer.Key) throws where EncodingContainer: KeyedEncodingContainerProtocol {
        var svc = container.superEncoder(forKey: key).singleValueContainer()
        if let value {
            try svc.encode(value)
        } else {
            try svc.encodeNil()
        }
    }
}
