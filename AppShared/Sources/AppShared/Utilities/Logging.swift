//
//  Logging.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.23.
//

import Foundation
import os

extension Logger {
  public static let shared = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "General")
  public static let api = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "API")
  /// Offline sync/fill/reconcile — the active server (DocumentStore /
  /// CachingRepository) and every inactive server (SyncEngine). Filter with
  /// `log stream --predicate 'category == "Sync"'` to watch the whole
  /// multi-server sync in isolation.
  public static let sync = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Sync")
  public static let migration = Logger(
    subsystem: Bundle.main.bundleIdentifier!, category: "Migration")
  public static let biometric = Logger(
    subsystem: Bundle.main.bundleIdentifier!, category: "Biometric")
}
