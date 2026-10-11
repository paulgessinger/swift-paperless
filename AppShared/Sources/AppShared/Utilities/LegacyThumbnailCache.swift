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
  /// Cheap when the directory is already gone: one failed stat.
  static func remove(under root: URL) {
    let url = AppGroup.Layout.legacyThumbnailCache(in: root)
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
