//
//  Logging.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.23.
//

import Foundation
import os

#if swift(>=6.0)
    #warning("Reevaluate whether this decoration is necessary.")
#endif

extension Logger {
    nonisolated(unsafe)
    static let shared = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "General")
    nonisolated(unsafe)
    static let api = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "API")
}
