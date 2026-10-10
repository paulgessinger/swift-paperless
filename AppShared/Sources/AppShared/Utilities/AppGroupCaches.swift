//
//  AppGroupCaches.swift
//  AppShared
//
//  The `Caches` directory of the app-group container, where the content
//  store and the thumbnail caches live.
//

import Common
import Foundation

enum AppGroupCaches {
  /// `<container>/Caches/<name>`; `nil` without an app-group container, and
  /// on macOS, where touching the group container from a test process raises
  /// a privacy prompt.
  static func directory(_ name: String) -> URL? {
    #if os(iOS)
      FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: ContentStore.appGroup
      )?.appendingPathComponent("Caches/\(name)", isDirectory: true)
    #else
      nil
    #endif
  }
}
