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

  static func enabled(_ feature: Self) -> Bool {
    return switch feature {
    case .tipJar: false  // disable for now until ready
    case .autoFocusSearchInDetailSheets: false
    }
  }
}
