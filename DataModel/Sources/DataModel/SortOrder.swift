//
//  SortOrder.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.06.2024.
//

import Foundation

public enum SortOrder: Codable, Sendable, Equatable {
  case ascending
  case descending

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let reverse = try container.decode(Bool.self)
    self.init(reverse)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(reverse)
  }

  public var reverse: Bool {
    switch self {
    case .descending:
      true
    case .ascending:
      false
    }
  }

  public init(_ reverse: Bool) {
    if reverse {
      self = .descending
    } else {
      self = .ascending
    }
  }
}
