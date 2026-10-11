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
  /// A variant is around the size of its thumbnail, tens of kilobytes; this
  /// holds thousands.
  static let sizeLimit = 150 * 1024 * 1024

  /// The cache under `root`, next to the content store; `nil` when its
  /// directory cannot be made.
  static func make(under root: URL) -> DataCache? {
    do {
      let cache = try DataCache(path: AppGroup.Layout.thumbnailVariants(in: root))
      cache.sizeLimit = sizeLimit
      return cache
    } catch {
      Logger.shared.error("Opening the thumbnail variant cache failed: \(error)")
      return nil
    }
  }
}
