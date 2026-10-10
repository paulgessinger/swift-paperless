//
//  LegacyThumbnailCache.swift
//  AppShared
//
//  Where builds before the file index kept Nuke's `DataCache`. Thumbnails
//  live in the content store now; the old directory is removed once.
//

import Foundation
import os

enum LegacyThumbnailCache {
  static var url: URL? { AppGroupCaches.directory("Nuke") }

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
