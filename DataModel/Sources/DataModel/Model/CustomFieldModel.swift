//
//  CustomFieldModel.swift
//  DataModel
//
//  Created by AI Assistant on 26.03.2024.
//

import Common
import Foundation
import MetaCodable

public enum CustomFieldDataType: RawRepresentable, Codable, Equatable, Hashable, Sendable {
  case string
  case url
  case date
  case boolean
  case integer
  case float
  case monetary
  case documentLink
  case select
  case other(String)

  // Added in https://github.com/paperless-ngx/paperless-ngx/pull/10846 v2.19.0
  case longText

  public init?(rawValue: String) {
    self =
      switch rawValue {
      case "string": .string
      case "longtext": .longText
      case "url": .url
      case "date": .date
      case "boolean": .boolean
      case "integer": .integer
      case "float": .float
      case "monetary": .monetary
      case "documentlink": .documentLink
      case "select": .select
      default: .other(rawValue)
      }
  }

  public var rawValue: String {
    switch self {
    case .string: "string"
    case .longText: "longtext"
    case .url: "url"
    case .date: "date"
    case .boolean: "boolean"
    case .integer: "integer"
    case .float: "float"
    case .monetary: "monetary"
    case .documentLink: "documentlink"
    case .select: "select"
    case .other(let value): value
    }
  }

  public static func == (lhs: CustomFieldDataType, rhs: CustomFieldDataType) -> Bool {
    switch (lhs, rhs) {
    case (.string, .string),
      (.longText, .longText),
      (.url, .url),
      (.date, .date),
      (.boolean, .boolean),
      (.integer, .integer),
      (.float, .float),
      (.monetary, .monetary),
      (.documentLink, .documentLink),
      (.select, .select):
      return true
    case (.other(let lValue), .other(let rValue)):
      return lValue == rValue
    default:
      return false
    }
  }
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct CustomFieldSelectOption: Identifiable, Hashable, Sendable {
  public var id: String
  public var label: String
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct CustomFieldExtraData: Sendable, Hashable {
  @Default([CustomFieldSelectOption]())
  public var selectOptions: [CustomFieldSelectOption]

  @Default(nil as String?)
  @CodedBy(NullCoder<String>())
  public var defaultCurrency: String?

  @usableFromInline
  static var `default`: Self { .init() }
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct CustomField: Identifiable, Model, Hashable, Named, Sendable {
  public typealias SelectOption = CustomFieldSelectOption
  public typealias ExtraData = CustomFieldExtraData
  public typealias DataType = CustomFieldDataType

  public var id: UInt
  public var name: String
  public var dataType: DataType

  @Default(CustomFieldExtraData.default)
  public var extraData: ExtraData

  @IgnoreEncoding
  @Default(nil as UInt?)
  public var documentCount: UInt?
}
