//
//  ApiTaskSource.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.26.
//

import DataModel
import Foundation

// V9 backends serve the full unpaginated array, so we cache the first fetch
// and serve client-side chunks to keep the UI responsive.
public actor ApiTaskSourceV9: PagedSource {
  public typealias Element = PaperlessTask
  private let repository: ApiRepository

  private var loaded: [PaperlessTask] = []
  private var cursor: Int = 0
  private var fetched: Bool = false

  init(repository: ApiRepository) {
    self.repository = repository
  }

  public func fetch(limit: UInt) async throws -> [PaperlessTask] {
    if !fetched {
      let request = try await repository.request(
        .tasks(name: .consumeFile, acknowledged: false))
      let decoded = try await repository.fetchData(for: request, as: [ApiTaskV9].self)
      loaded = decoded.map(\.domain)
      fetched = true
    }
    let remaining = loaded.count - cursor
    let take = Int(min(UInt(remaining), limit))
    let result = Array(loaded[cursor..<cursor + take])
    cursor += take
    return result
  }

  public var isExhausted: Bool { fetched && cursor >= loaded.count }
  public var totalCount: UInt? { fetched ? UInt(loaded.count) : nil }
}
