//
//  SettingValueCoder.swift
//  Common
//
//  Created by Paul Gessinger on 26.07.26.
//

import Foundation

/// Translates a setting value to and from what is actually put in
/// `UserDefaults`.
///
/// Settings used to be stored as JSON `Data` without exception, so a `Bool`
/// was the four bytes `true`. That is invisible in a defaults dump, cannot be
/// observed with KVO, is not readable by `@AppStorage`, and would go into
/// `NSUbiquitousKeyValueStore` as an opaque blob.
///
/// Values whose JSON form is a single scalar are therefore stored as the
/// native type instead. The scalar is derived from the value's own `Codable`
/// conformance rather than from a separate mapping, so what is written matches
/// what the JSON form has always contained — no type can drift between the two
/// representations. Anything composite (an object or an array) stays `Data`.
enum SettingValueCoder {
  /// What a value looks like in `UserDefaults`.
  enum Stored: Equatable {
    case bool(Bool)
    case string(String)
    case json(Data)
  }

  static func encode(_ value: some Encodable) throws -> Stored {
    let data = try JSONEncoder().encode(value)

    // A JSON scalar: store it as the matching native type. The decode attempts
    // are cheap and unambiguous — JSONDecoder does not coerce between a bool,
    // a string and a container.
    if let bool = try? JSONDecoder().decode(Bool.self, from: data) {
      return .bool(bool)
    }
    if let string = try? JSONDecoder().decode(String.self, from: data) {
      return .string(string)
    }
    return .json(data)
  }

  static func decode<Value: Decodable>(_ type: Value.Type, from stored: Stored) throws -> Value {
    switch stored {
    case .bool(let bool):
      try JSONDecoder().decode(type, from: JSONEncoder().encode(bool))
    case .string(let string):
      // Re-encoded rather than quoted by hand, so escaping stays the
      // encoder's problem.
      try JSONDecoder().decode(type, from: JSONEncoder().encode(string))
    case .json(let data):
      try JSONDecoder().decode(type, from: data)
    }
  }

  /// Reads whatever is under `key`, in either the native or the legacy form.
  ///
  /// `Data` is checked first: a value written before the migration is JSON,
  /// and only a genuinely composite value stays that way afterwards.
  static func read(from suite: UserDefaults, key: String) -> Stored? {
    switch suite.object(forKey: key) {
    case let data as Data: .json(data)
    case let string as String: .string(string)
    case let bool as Bool: .bool(bool)
    default: nil
    }
  }

  static func write(_ stored: Stored, to suite: UserDefaults, key: String) {
    switch stored {
    case .bool(let bool): suite.set(bool, forKey: key)
    case .string(let string): suite.set(string, forKey: key)
    case .json(let data): suite.set(data, forKey: key)
    }
  }
}
