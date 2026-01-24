//
//  FeatureFlags.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 24.01.26.
//

import Foundation

enum AppFeatures {
  case tipJar

  static func enabled(_ feature: Self) -> Bool {
    let channel = Bundle.main.appConfiguration

    return switch feature {
    case .tipJar: channel != .AppStore
    }
  }
}
