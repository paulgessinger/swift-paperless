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
  public static let migration = Logger(
    subsystem: Bundle.main.bundleIdentifier!, category: "Migration")
  public static let biometric = Logger(
    subsystem: Bundle.main.bundleIdentifier!, category: "Biometric")
}
