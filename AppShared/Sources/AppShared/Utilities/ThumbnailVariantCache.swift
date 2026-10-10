//
//  ThumbnailVariantCache.swift
//  AppShared
//
//  The resized thumbnails the image pipeline derives for the list cells.
//  They are recreated from the stored thumbnail whenever they are missing,
//  so a plain least-recently-used cache with a size cap is all they need.
//

import Foundation
import Nuke
import os

enum ThumbnailVariantCache {
  /// A variant is around ten kilobytes as JPEG; this holds over ten thousand.
  static let sizeLimit = 150 * 1024 * 1024

  static var url: URL? { AppGroupCaches.directory("ThumbnailVariants") }

  /// `nil` without an app-group container (previews, host tests).
  static func make() -> DataCache? {
    guard let url else { return nil }
    do {
      return try make(at: url)
    } catch {
      Logger.shared.error("Opening the thumbnail variant cache failed: \(error)")
      return nil
    }
  }

  static func make(at url: URL) throws -> DataCache {
    let cache = try DataCache(path: url)
    cache.sizeLimit = sizeLimit
    return cache
  }
}
