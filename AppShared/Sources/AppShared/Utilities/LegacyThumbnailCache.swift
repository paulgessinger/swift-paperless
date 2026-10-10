//
//  LegacyThumbnailCache.swift
//  AppShared
//
//  Where builds before the file index kept Nuke's `DataCache`. Thumbnails
//  live in the content store now; the old directory is removed once.
//

import Common
import Foundation
import os

enum LegacyThumbnailCache {
  /// `nil` without an app-group container, and on macOS, where touching the
  /// group container from a test process raises a privacy prompt.
  static var url: URL? {
    #if os(iOS)
      FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: ContentStore.appGroup
      )?.appendingPathComponent("Caches/Nuke", isDirectory: true)
    #else
      nil
    #endif
  }

  /// Cheap when the directory is already gone: one failed stat.
  static func remove() {
    guard let url else { return }
    do {
      try FileManager.default.removeItem(at: url)
      Logger.shared.info("Removed the legacy thumbnail cache")
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
    {
      // Already gone.
    } catch {
      Logger.shared.debug("Removing the legacy thumbnail cache failed: \(error)")
    }
  }
}
