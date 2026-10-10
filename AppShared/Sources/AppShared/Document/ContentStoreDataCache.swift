//
//  ContentStoreDataCache.swift
//  AppShared
//
//  Nuke's disk cache, backed by the content store and the file index: a
//  thumbnail lives next to its document's files and is recorded like them.
//

import Common
import Foundation
import Nuke
import os

/// Stores the server's thumbnail bytes at the version's `thumbnail.bin` and
/// records the row. Lookups are a file-system check, since Nuke calls them
/// synchronously; the index write runs on its own.
///
/// Keys that ``ThumbnailImageID`` cannot parse (a URL, or an id with a
/// processor suffix) are not cached: nothing is read or written for them.
public final class ContentStoreDataCache: DataCaching, Sendable {
  private let store: ContentStore
  private let index: any FileIndex

  public init(store: ContentStore, index: any FileIndex) {
    self.store = store
    self.index = index
  }

  public func cachedData(for key: String) -> Data? {
    guard let parsed = ThumbnailImageID.parse(key) else { return nil }
    return try? Data(contentsOf: store.url(for: parsed.key))
  }

  public func containsData(for key: String) -> Bool {
    guard let parsed = ThumbnailImageID.parse(key) else { return false }
    return store.exists(parsed.key)
  }

  public func storeData(_ data: Data, for key: String) {
    guard let parsed = ThumbnailImageID.parse(key) else { return }
    let store = store
    let index = index
    // File first, row second, like a download.
    Task.detached(priority: .utility) {
      do {
        try store.storeData(data, for: parsed.key)
        try await index.recordStore(
          parsed.key, documentID: parsed.documentID,
          size: store.size(of: parsed.key) ?? Int64(data.count), modified: nil, checksum: nil,
          storedAt: Date())
      } catch {
        Logger.shared.debug("Storing a thumbnail failed: \(error)")
      }
    }
  }

  public func removeData(for key: String) {
    guard let parsed = ThumbnailImageID.parse(key) else { return }
    let store = store
    let index = index
    Task.detached(priority: .utility) {
      try? store.delete(parsed.key)
      try? await index.forget(parsed.key)
    }
  }

  /// Nothing: the files belong to the content store, which the cache wipe
  /// purges along with their rows.
  public func removeAll() {}
}
