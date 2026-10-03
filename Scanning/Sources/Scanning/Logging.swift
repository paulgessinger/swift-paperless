//
//  Logging.swift
//  Scanning
//

import os

extension Logger {
  /// One category for the whole scanning subsystem — discovery, capabilities,
  /// the scan itself and the UI driving it, including the parts that live in
  /// the app target. Public for that last reason: it is what makes
  /// `log stream --predicate 'category == "Scanning"'` show the entire flow.
  public static let scanning = Logger(
    subsystem: "com.paulgessinger.swift-paperless", category: "Scanning")
}
