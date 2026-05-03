//
//  ApiTaskSource.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.26.
//

import DataModel
import Foundation

// V10 backends paginate via the standard ListResponse envelope; we drive the
// fetch through ApiSequence and map each wire item to its domain type.
public actor ApiTaskSourceV10: TaskSource {
  private let sequence: ApiSequence<ApiTaskV10>

  init(repository: ApiRepository, initialUrl: URL) {
    sequence = ApiSequence<ApiTaskV10>(repository: repository, url: initialUrl)
  }

  public func fetch(limit: UInt) async throws -> [PaperlessTask] {
    var batch: [PaperlessTask] = []
    while UInt(batch.count) < limit {
      guard let item = try await sequence.next() else { break }
      batch.append(item.domain)
    }
    return batch
  }

  public func hasMore() async -> Bool {
    await sequence.hasMore
  }
}

// V9 backends serve the full unpaginated array, so we cache the first fetch
// and serve client-side chunks to keep the UI responsive.
public actor ApiTaskSourceV9: TaskSource {
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

  public func hasMore() async -> Bool {
    !fetched || cursor < loaded.count
  }
}
