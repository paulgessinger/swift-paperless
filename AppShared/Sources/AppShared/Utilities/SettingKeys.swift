//
//  SettingKeys.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.07.26.
//

import Common
import DataModel
import Foundation

// The app's settings, declared once each. The name is the key the value is
// stored under: it is persisted user data, so renaming one orphans what users
// already have stored.
//
// Everything is `.device` for now, which is where these values have always
// been written. Moving a key to `.shared` (so the ShareExtension can read it)
// needs a migration of the existing value and is deliberately not part of this
// change.
extension SettingKey {
  public static var documentDeleteConfirmation: SettingKey<Bool> {
    .init("documentDeleteConfirmation", default: true)
  }

  /// Not a candidate for syncing across devices: the enrolled biometrics
  /// differ per device, so syncing this would arm the lock on a device the
  /// user never configured.
  public static var enableBiometricAppLock: SettingKey<Bool> {
    .init("enableBiometricAppLock", default: false)
  }

  public static var defaultSearchMode: SettingKey<FilterState.SearchMode> {
    .init("defaultSearchMode", default: .titleContent)
  }

  public static var defaultSortField: SettingKey<SortField> {
    .init("defaultSortField", default: .added)
  }

  public static var defaultSortOrder: SettingKey<DataModel.SortOrder> {
    .init("defaultSortOrder", default: .descending)
  }

  public static var filterBarConfiguration: SettingKey<FilterBarConfiguration> {
    .init("filterBarConfiguration", default: .default)
  }

  public static var offlineBrowsingMode: SettingKey<AppSettings.OfflineBrowsingMode> {
    .init("offlineBrowsingMode", default: .recentlyBrowsed)
  }

  /// The version this install last launched, which drives the release-notes
  /// sheet. Per-install by definition.
  public static var currentAppVersion: SettingKey<AppVersion?> {
    .init("currentAppVersion", default: nil)
  }
}
