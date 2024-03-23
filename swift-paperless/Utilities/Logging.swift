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
}
