//
//  FeatureFlags.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 24.01.26.
//

import Foundation

enum AppFeatures {
  case tipJar
  case documentDetailViewV4
  case autoFocusSearchInDetailSheets

  static func enabled(_ feature: Self) -> Bool {
    let channel = Bundle.main.appConfiguration

    return switch feature {
    case .tipJar: true
    case .documentDetailViewV4:
      switch channel {
      case .Debug, .Simulator, .TestFlight, .AppStore:
        true
      }
    case .autoFocusSearchInDetailSheets: false
    }
  }
}
