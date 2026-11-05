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
  /// The opt-in UI only runs in debug builds until telemetry exists and the
  /// privacy policy describes it.
  case telemetry

  static func enabled(_ feature: Self) -> Bool {
    return switch feature {
    case .tipJar: true
    case .autoFocusSearchInDetailSheets: false
    case .telemetry: Bundle.isDebug
    }
  }
}
