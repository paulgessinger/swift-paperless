//
//  FeatureFlags.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 24.01.26.
//

import AppShared
import Foundation

enum AppFeatures {
  case tipJar
  case autoFocusSearchInDetailSheets
  case networkScanner

  static func enabled(_ feature: Self) -> Bool {
    return switch feature {
    case .tipJar: true
    case .autoFocusSearchInDetailSheets: false
    // Scanning over eSCL has only been exercised against one printer, and the
    // page-fetch half not at all. Debug, Simulator and TestFlight get it so it
    // can be, but it stays out of the App Store build until it has been.
    case .networkScanner: Bundle.main.appConfiguration != .AppStore
    }
  }
}
