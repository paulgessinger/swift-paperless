//
//  SettingsStore+shared.swift
//  Common
//
//  Created by Paul Gessinger on 26.07.26.
//

import Foundation

extension SettingsStore {
  /// The store the app and the ShareExtension read their settings from.
  ///
  /// Tests construct their own store with dedicated suites instead.
  public static let shared = SettingsStore(
    suites: [
      .device: .standard,
      .shared: UserDefaults(suiteName: AppGroup.identifier) ?? .standard,
    ]
  )
}
