//
//  AppGroup.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.05.26.
//

import Foundation

/// The single source of truth for the shared app-group identifier used by the
/// main app, the Share Extension, and any future extensions (e.g. File
/// Provider) to reach shared containers and `UserDefaults`, and for what
/// lives where in that container.
///
/// The `.entitlements` files must repeat this literal — Xcode reads them before
/// any Swift runs — but every Swift call site should reference this constant
/// rather than hard-coding the string.
public enum AppGroup {
  public static let identifier = "group.com.paulgessinger.swift-paperless"

  /// The shared container; `nil` when the process has no entitlement for it.
  public static func container(identifier: String = identifier) -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
  }

  /// Every path under the container, relative to a root so that tests can put
  /// a temporary directory in the container's place.
  public enum Layout {
    /// The SQLite database, shared by every server; `-wal` and `-shm` next to it.
    public static func database(in root: URL) -> URL {
      root
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Database", isDirectory: true)
        .appendingPathComponent("swift-paperless.sqlite")
    }

    /// Downloaded document files and thumbnails, by server and version: the
    /// ``ContentStore``. Under Application Support, not Caches: iOS purges
    /// Caches under storage pressure, and the library's files must stay.
    public static func contentStore(in root: URL) -> URL {
      root
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("ContentStore", isDirectory: true)
    }

    /// Where builds before the library download kept the store; moved once.
    public static func legacyContentStore(in root: URL) -> URL {
      root.appendingPathComponent("Caches/ContentStore", isDirectory: true)
    }

    /// The resized thumbnails the image pipeline derives, a size-capped cache.
    public static func thumbnailVariants(in root: URL) -> URL {
      root.appendingPathComponent("Caches/ThumbnailVariants", isDirectory: true)
    }

    /// Nuke's `DataCache` in builds before the file index; removed at launch.
    public static func legacyThumbnailCache(in root: URL) -> URL {
      root.appendingPathComponent("Caches/Nuke", isDirectory: true)
    }
  }
}
