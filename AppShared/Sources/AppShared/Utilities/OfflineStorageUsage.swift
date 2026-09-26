//
//  OfflineStorageUsage.swift
//  swift-paperless
//
//  What the offline data occupies on disk, for the Offline & Sync screen's
//  Storage section. The measuring itself lives in Common (`DiskUsage`,
//  `ContentStore.usage()`) and Persistence (`Database.diskUsage()`), where it
//  is host-tested; this only gathers the three stores in one place.
//

import Common
import Foundation
import Nuke
import Persistence

public struct OfflineStorageUsage: Sendable, Equatable {
  /// The SQLite cache, shared by every server.
  public var database: DiskUsage
  /// Downloaded originals/archives in the app-group `ContentStore`, split by server.
  public var content: ContentStore.Usage
  /// Nuke's thumbnail caches, which carry no server identity.
  public var thumbnails: DiskUsage

  public init(
    database: DiskUsage = .zero, content: ContentStore.Usage = .init(),
    thumbnails: DiskUsage = .zero
  ) {
    self.database = database
    self.content = content
    self.thumbnails = thumbnails
  }

  public var totalBytes: Int64 {
    database.bytes + content.total.bytes + thumbnails.bytes
  }

  /// Walk every store. Blocking file-system I/O proportional to the number of
  /// cached files, so never call it on the main actor — ``DocumentStore/storageUsage()``
  /// runs it detached.
  ///
  /// Each store measures as zero when it can't be reached (no app-group
  /// container in previews, or no database before login), so the section
  /// shows what exists instead of failing as a whole.
  static func measure(database: Database?) -> OfflineStorageUsage {
    OfflineStorageUsage(
      database: database?.diskUsage() ?? .zero,
      content: (try? ContentStore())?.usage() ?? .init(),
      thumbnails: measureThumbnails())
  }

  /// The app-group `DataCache` the image pipelines write to, plus Nuke's own
  /// `URLCache`.
  ///
  /// Both, because `DocumentStore.makeImagePipeline` adds the `DataCache`
  /// without disabling the `URLCache` that Nuke's `DataLoader` installs by
  /// default, so a thumbnail can sit in each. The `URLCache` lives in this
  /// process's own caches directory, so the Share Extension's copy isn't
  /// counted — it's small and not something the app can see anyway.
  private static func measureThumbnails() -> DiskUsage {
    var usage = DocumentStore.thumbnailCacheURL().map { DiskUsage.measure($0) } ?? .zero
    // `URLCache` reports bytes only; its on-disk layout is private, so no file count.
    usage.bytes += Int64(DataLoader.sharedUrlCache.currentDiskUsage)
    return usage
  }
}
