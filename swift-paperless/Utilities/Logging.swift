//
//  Logging.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.23.
//

import Foundation
import os

extension Logger {
  static let shared = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "General")
  static let api = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "API")
  static let migration = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Migration")
  static let biometric = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Biometric")
}
