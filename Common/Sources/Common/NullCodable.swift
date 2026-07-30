//
//  NullCodable.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.08.23.
//

import Foundation

/// Encodes and decodes optional values using explicit JSON `null` instead of omitting the key.
///
/// Use this when an API treats a missing key as "unchanged" but `null` as cleared.
@propertyWrapper
public struct NullCodable<T: Codable & Sendable>: Codable, Sendable {
  public var wrappedValue: T?

  public init(wrappedValue: T?) {
    self.wrappedValue = wrappedValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      wrappedValue = nil
    } else {
      wrappedValue = try container.decode(T.self)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    if let wrappedValue {
      try container.encode(wrappedValue)
    } else {
      try container.encodeNil()
    }
  }
}
