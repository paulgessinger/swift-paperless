//
//  AppFeatures.swift
//  AppShared
//
//  Created by Paul Gessinger on 24.01.26.
//

import Foundation

/// Build-dependent feature switches, shared by the app and its extensions.
public enum AppFeatures: Sendable {
  case tipJar
  case autoFocusSearchInDetailSheets
  /// Telemetry and its opt-in UI only run in debug builds until the privacy
  /// policy describes it.
  case telemetry
  case networkScanner

  public static func enabled(_ feature: Self) -> Bool {
    return switch feature {
    case .tipJar: true
    case .autoFocusSearchInDetailSheets: false
    case .telemetry: Bundle.isDebug
    // Scanning over eSCL has only been exercised against one printer, and the
    // page-fetch half not at all. Debug, Simulator and TestFlight get it so it
    // can be, but it stays out of the App Store build until it has been.
    case .networkScanner: Bundle.main.appConfiguration != .AppStore
    }
  }
}
