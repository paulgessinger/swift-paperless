//
//  FeatureFlags.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 24.01.26.
//

import Foundation

enum AppFeatures {
  case tipJar
  case autoFocusSearchInDetailSheets
  /// The opt-in UI only runs in debug simulator builds until telemetry exists
  /// and the privacy policy describes it.
  case telemetry

  private static var isDebugSimulator: Bool {
    #if DEBUG && targetEnvironment(simulator)
      true
    #else
      false
    #endif
  }

  static func enabled(_ feature: Self) -> Bool {
    return switch feature {
    case .tipJar: true
    case .autoFocusSearchInDetailSheets: false
    case .telemetry: isDebugSimulator
    }
  }
}
