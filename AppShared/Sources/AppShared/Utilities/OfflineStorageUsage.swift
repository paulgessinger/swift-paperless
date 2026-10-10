//
//  OfflineStorageUsage.swift
//  swift-paperless
//
//  What the offline data occupies on disk, for the Offline & Sync screen's
//  Storage section. The database measures its own files; the downloaded
//  files and thumbnails are summed from the file index, no directory walk.
//

import Common
import Foundation
import Nuke
import Persistence

public struct OfflineStorageUsage: Sendable, Equatable {
  /// The SQLite cache, shared by every server.
  public var database: DiskUsage
  /// The indexed files. Thumbnails also carry whatever Nuke's `URLCache`
  /// still holds.
  public var files: FileUsage

  public init(database: DiskUsage = .zero, files: FileUsage = FileUsage()) {
    self.database = database
    self.files = files
  }

  public var totalBytes: Int64 {
    database.bytes + files.documents.bytes + files.thumbnails.bytes
  }

  /// Measure the database's files and read the index. The file walk is
  /// blocking, so ``DocumentStore/storageUsage()`` runs this detached.
  ///
  /// Each figure is zero when it can't be reached (no database before login),
  /// so the section shows what exists instead of failing as a whole.
  static func measure(database: Database?) async -> OfflineStorageUsage {
    var files = FileUsage()
    if let database, let read = try? await database.fileUsage() {
      files = read
    }
    // The `URLCache` is switched off wherever the content store exists, so
    // nothing adds to it any more. It is still read, because what a build from
    // before that change wrote is still on disk: the app never empties it, and
    // iOS keeps charging it to the app until it decides to evict it. It also
    // stays the only cache where there is no store at all (previews, host
    // tests). Bytes only; its on-disk layout is private, so no file count.
    files.thumbnails.bytes += Int64(DataLoader.sharedUrlCache.currentDiskUsage)
    return OfflineStorageUsage(database: database?.diskUsage() ?? .zero, files: files)
  }
}
