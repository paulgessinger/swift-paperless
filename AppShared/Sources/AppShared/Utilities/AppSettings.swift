//
//  AppSettings.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.08.23.
//
import Common
import DataModel
import Foundation
import os

/// The app's global settings.
///
/// Every setting is a computed property over ``SettingsStore``, which owns
/// encoding, caching and the choice of `UserDefaults` suite. The keys, with
/// their defaults, are declared in `SettingKeys.swift`.
///
/// Settings that belong to a single server connection do not live here — those
/// are stored with the connection in the database.
@MainActor
@Observable
public final class AppSettings {
  public static let shared = AppSettings()

  @ObservationIgnored
  private let store: SettingsStore

  /// The version this install ran before the current launch, or `nil` on a
  /// fresh install. Read once at startup, before the current version is
  /// recorded.
  public private(set) var lastAppVersion: AppVersion?

  private init(store: SettingsStore = .shared) {
    self.store = store

    lastAppVersion = store[.currentAppVersion]
    Logger.shared.info(
      "Last app version was: \(self.lastAppVersion?.description ?? "?", privacy: .public)")

    var release = Bundle.main.releaseVersionNumber
    if release == nil {
      Logger.shared.warning("Current release version number is nil")
      release = "1.0.0"
    }
    var build = Bundle.main.buildVersionNumber
    if build == nil {
      Logger.shared.warning("Current build number is nil")
      build = "1"
    }

    guard let release, let build, let currentVersion = AppVersion(version: release, build: build)
    else {
      return
    }

    Logger.shared.info("Current app version is: \(currentVersion, privacy: .public)")
    store[.currentAppVersion] = currentVersion
  }

  public var documentDeleteConfirmation: Bool {
    get {
      access(keyPath: \.documentDeleteConfirmation)
      return store[.documentDeleteConfirmation]
    }
    set {
      withMutation(keyPath: \.documentDeleteConfirmation) {
        store[.documentDeleteConfirmation] = newValue
      }
    }
  }

  public var enableBiometricAppLock: Bool {
    get {
      access(keyPath: \.enableBiometricAppLock)
      return store[.enableBiometricAppLock]
    }
    set {
      withMutation(keyPath: \.enableBiometricAppLock) {
        store[.enableBiometricAppLock] = newValue
      }
    }
  }

  public var defaultSearchMode: FilterState.SearchMode {
    get {
      access(keyPath: \.defaultSearchMode)
      return store[.defaultSearchMode]
    }
    set {
      withMutation(keyPath: \.defaultSearchMode) {
        store[.defaultSearchMode] = newValue
      }
    }
  }

  public var defaultSortField: SortField {
    get {
      access(keyPath: \.defaultSortField)
      return store[.defaultSortField]
    }
    set {
      withMutation(keyPath: \.defaultSortField) {
        store[.defaultSortField] = newValue
      }
    }
  }

  public var defaultSortOrder: DataModel.SortOrder {
    get {
      access(keyPath: \.defaultSortOrder)
      return store[.defaultSortOrder]
    }
    set {
      withMutation(keyPath: \.defaultSortOrder) {
        store[.defaultSortOrder] = newValue
      }
    }
  }

  public var filterBarConfiguration: FilterBarConfiguration {
    get {
      access(keyPath: \.filterBarConfiguration)
      return store[.filterBarConfiguration]
    }
    set {
      withMutation(keyPath: \.filterBarConfiguration) {
        store[.filterBarConfiguration] = newValue
      }
    }
  }

  public var currentAppVersion: AppVersion? {
    get {
      access(keyPath: \.currentAppVersion)
      return store[.currentAppVersion]
    }
    set {
      withMutation(keyPath: \.currentAppVersion) {
        store[.currentAppVersion] = newValue
      }
    }
  }

  /// Forgets the recorded app version, so the next launch behaves like an
  /// upgrade from an unknown version. Used by the debug menu to bring the
  /// release notes back.
  public func resetAppVersion() {
    Logger.shared.info("Resetting stored app version")
    withMutation(keyPath: \.currentAppVersion) {
      store.remove(.currentAppVersion)
    }
  }
}
