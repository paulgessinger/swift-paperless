import os

extension Logger {
  static let common = Logger(subsystem: "com.paulgessinger.swift-paperless", category: "Common")
  static let cache = Logger(subsystem: "com.paulgessinger.swift-paperless", category: "Cache")
}
