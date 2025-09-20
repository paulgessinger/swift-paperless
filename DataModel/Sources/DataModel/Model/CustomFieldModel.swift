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

  public init?(rawValue: String) {
    self =
      switch rawValue {
      case "string": .string
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
