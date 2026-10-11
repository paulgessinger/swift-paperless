//
//  ThumbnailVariantCache.swift
//  AppShared
//
//  The resized thumbnails the image pipeline derives for the list cells.
//  They are recreated from the stored thumbnail whenever they are missing,
//  so a plain least-recently-used cache with a size cap is all they need.
//

import Common
import Foundation
import Nuke
import os

enum ThumbnailVariantCache {
  /// The cache under `root`, next to the content store; `nil` when its
  /// directory cannot be made.
  static func make(under root: URL) -> DataCache? {
    do {
      let cache = try DataCache(path: AppGroup.Layout.thumbnailVariants(in: root))
      cache.sizeLimit = StoragePolicy.thumbnailVariantCacheBytes
      return cache
    } catch {
      Logger.shared.error("Opening the thumbnail variant cache failed: \(error)")
      return nil
    }
  }
}
