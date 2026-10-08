//
//  BackgroundTime.swift
//  swift-paperless
//

import AppShared
import Persistence
import UIKit
import os

/// The app's ``DatabaseSuspensionController/RequestTime``: time to keep
/// running in the background, from `UIApplication.beginBackgroundTask`.
@MainActor
enum BackgroundTime {
  static func request(
    onExpire: @escaping @MainActor @Sendable () -> Void
  ) -> @MainActor () -> Void {
    let grant = Grant()
    // UIKit calls this on the main thread; the grant must end before it returns.
    grant.id = UIApplication.shared.beginBackgroundTask(withName: "Database writes") {
      MainActor.assumeIsolated {
        onExpire()
        grant.end()
      }
    }
    if grant.id == .invalid {
      // The work may still run under another grant (an App Intent, a background
      // task), and is cut off when that one ends.
      Logger.shared.notice("No background time granted for database writes")
    }
    return { grant.end() }
  }

  @MainActor
  private final class Grant {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
      guard id != .invalid else { return }
      UIApplication.shared.endBackgroundTask(id)
      id = .invalid
    }
  }
}
