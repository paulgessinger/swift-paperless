//
//  ApiPagedSource.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.26.
//

import DataModel
import Foundation

// Generic PagedSource adapter that drives a PageCursor and maps each wire item
// to a domain item.
public actor ApiPagedSource<Wire: Decodable & Sendable, Domain: Sendable>: PagedSource {
  public typealias Element = Domain

  private let cursor: PageCursor<Wire>
  private let map: @Sendable (Wire) -> Domain
  private var buffer: [Domain] = []
  private var cursorExhausted: Bool = false

  public init(cursor: PageCursor<Wire>, map: @Sendable @escaping (Wire) -> Domain) {
    self.cursor = cursor
    self.map = map
  }

  public func fetch(limit: UInt) async throws -> [Domain] {
    while UInt(buffer.count) < limit, !cursorExhausted {
      guard let page = try await cursor.nextPage() else {
        cursorExhausted = true
        break
      }
      buffer.append(contentsOf: page.items.map(map))
      if page.isLast {
        cursorExhausted = true
      }
    }
    let take = Int(min(UInt(buffer.count), limit))
    let head = Array(buffer.prefix(take))
    buffer.removeFirst(take)
    return head
  }

  public var isExhausted: Bool {
    get async { cursorExhausted && buffer.isEmpty }
  }

  public var totalCount: UInt? {
    get async { await cursor.totalCount }
  }
}
