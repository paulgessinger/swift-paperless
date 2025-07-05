//
//  TagModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Common
import Foundation
import MetaCodable
import SwiftUI

public protocol TagProtocol:
  Equatable,
  MatchingModel,
  Sendable
{
  var isInboxTag: Bool { get set }
  var name: String { get set }
  var slug: String { get set }
  var color: HexColor { get set }
  var textColor: HexColor { get }

  static func placeholder(_ length: Int) -> Self
}

extension TagProtocol {
  public var textColor: HexColor {
    HexColor(color.color.luminance < 0.53 ? .white : .black)
  }
}

private var placeholderColor: Color {
  #if canImport(UIKit)
    Color(uiColor: UIColor.systemGroupedBackground)
  #else
    .gray
  #endif
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct ProtoTag: TagProtocol, MatchingModel {
  @Default(false)
  public var isInboxTag: Bool

  @Default("")
  public var name: String

  @Default("")
  public var slug: String

  @Default(Color.gray.hex)
  public var color: HexColor

  @Default("")
  public var match: String

  @Default(MatchingAlgorithm.auto)
  public var matchingAlgorithm: MatchingAlgorithm

  @Default(true)
  public var isInsensitive: Bool

  public static func placeholder(_ length: Int) -> Self {
    let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    let name = String((0..<length).map { _ in letters.randomElement()! })
    return .init(
      isInboxTag: false,
      name: name,
      slug: "",
      color: placeholderColor.hex
    )
  }

  // For PermissionsModel conformance
  @Default(Owner.unset)
  public var owner: Owner

  // Presence of this depends on the endpoint
  @IgnoreEncoding
  public var permissions: Permissions? {
    didSet {
      setPermissions = permissions
    }
  }

  // The API wants this extra key for writing perms
  public var setPermissions: Permissions?
}

extension ProtoTag: PermissionsModel {}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct Tag: Identifiable, Model, TagProtocol, MatchingModel, Equatable, Hashable, Sendable {
  public var id: UInt
  public var isInboxTag: Bool
  public var name: String
  public var slug: String
  public var color: HexColor
  public var match: String
  public var matchingAlgorithm: MatchingAlgorithm
  public var isInsensitive: Bool

  public static func placeholder(_ length: Int) -> Self {
    let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    let name = String((0..<length).map { _ in letters.randomElement()! })

    return .init(
      id: 0,
      isInboxTag: false,
      name: name,
      slug: "",
      color: placeholderColor.hex,
      match: "",
      matchingAlgorithm: .auto,
      isInsensitive: true
    )
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}
