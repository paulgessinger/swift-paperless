//
//  ListResponse.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.05.23.
//

import Foundation

public struct ListResponse<Element> {
  public var count: UInt
  public var next: URL?
  public var previous: URL?
  public var results: [Element]
}

extension ListResponse: Decodable
where Element: Decodable {}

extension ListResponse: Sendable where Element: Sendable {}
