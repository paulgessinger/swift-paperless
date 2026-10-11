//
//  ContentStoreDataCache.swift
//  AppShared
//
//  Nuke's disk cache, backed by the content store and the file index: a
//  thumbnail lives next to its document's files and is recorded like them.
//  The resized variants the pipeline derives from it go to a plain LRU cache.
//

import Common
import Foundation
import Nuke
import os

/// Stores the server's thumbnail bytes at the version's `thumbnail.bin` and
/// records the row. Lookups are a file-system check, since Nuke calls them
/// synchronously; the index write runs on its own.
///
/// A key with a processor suffix is a resized variant: recreatable from the
/// stored bytes, so it goes to `variants`, a size-capped cache with no index
/// row, and is simply not cached without one. Nuke writes a variant when the
/// thumbnail comes from the network, not when it is derived from a disk hit,
/// so one the cap dropped is derived in memory until the thumbnail is fetched
/// again. Keys ``ThumbnailImageID`` does not recognise (a URL) are neither
/// read nor written.
public final class ContentStoreDataCache: DataCaching, Sendable {
  private let store: ContentStore
  private let index: any FileIndex
  public let variants: DataCache?

  public init(store: ContentStore, index: any FileIndex, variants: DataCache? = nil) {
    self.store = store
    self.index = index
    self.variants = variants
  }

  public func cachedData(for key: String) -> Data? {
    if let parsed = ThumbnailImageID.parse(key) {
      return try? Data(contentsOf: store.url(for: parsed.key))
    }
    return variantCache(for: key)?.cachedData(for: key)
  }

  public func containsData(for key: String) -> Bool {
    if let parsed = ThumbnailImageID.parse(key) {
      return store.exists(parsed.key)
    }
    return variantCache(for: key)?.containsData(for: key) ?? false
  }

  public func storeData(_ data: Data, for key: String) {
    guard let parsed = ThumbnailImageID.parse(key) else {
      variantCache(for: key)?.storeData(data, for: key)
      return
    }
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
    guard let parsed = ThumbnailImageID.parse(key) else {
      variantCache(for: key)?.removeData(for: key)
      return
    }
    let store = store
    let index = index
    Task.detached(priority: .utility) {
      try? store.delete(parsed.key)
      try? await index.forget(parsed.key)
    }
  }

  /// Only the variants: the files belong to the content store, which the
  /// cache wipe purges along with their rows.
  public func removeAll() {
    variants?.removeAll()
  }

  private func variantCache(for key: String) -> DataCache? {
    guard let variants, ThumbnailImageID.isVariant(key) else { return nil }
    return variants
  }
}
