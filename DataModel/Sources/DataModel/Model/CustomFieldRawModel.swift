//
//  CustomFieldRawModel.swift
//  DataModel
//
//  Created by AI Assistant on 26.03.2024.
//

import Foundation

public struct CustomFieldUnknownValue: Error {}

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
    case (.string(let lhs), .string(let rhs)):
      lhs == rhs
    case (.float(let lhs), .float(let rhs)):
      lhs == rhs
    case (.integer(let lhs), .integer(let rhs)):
      lhs == rhs
    case (.boolean(let lhs), .boolean(let rhs)):
      lhs == rhs
    case (.idList(let lhs), .idList(let rhs)):
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
    // @FIXME: Float without decimals is decoded as an integer, which leads to a problem!
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
    case .string(let value):
      try container.encode(value)
    case .float(let value):
      try container.encode(value)
    case .integer(let value):
      try container.encode(value)
    case .boolean(let value):
      try container.encode(value)
    case .idList(let value):
      try container.encode(value)
    case .none:
      try container.encodeNil()
    case .unknown:
      throw CustomFieldUnknownValue()
    }
  }
}

public struct CustomFieldRawEntryList: Codable, Sendable, Equatable, Hashable,
  RandomAccessCollection
{
  public typealias Element = CustomFieldRawEntry
  public typealias Index = Int
  public typealias SubSequence = ArraySlice<CustomFieldRawEntry>

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

  public subscript(bounds: Range<Int>) -> SubSequence {
    values[bounds]
  }

  public var startIndex: Int {
    values.startIndex
  }

  public var endIndex: Int {
    values.endIndex
  }
}

public struct CustomFieldRawEntry: Codable, Sendable, Equatable, Hashable {
  public var field: UInt
  public var value: CustomFieldRawValue
}
