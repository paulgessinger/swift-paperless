//
//  AppSettings.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.08.23.
//
import Common
import DataModel
import Foundation
import Observation
import os

/// The app's global settings.
///
/// Every setting is `@Setting`-expanded access to ``SettingsStore``, which owns
/// encoding, caching and the choice of `UserDefaults` suite. The keys, with
/// their defaults, are declared in `SettingKeys.swift`.
///
/// Observation is wired up by hand rather than with `@Observable`: the macro
/// claims the accessors of every stored property, which collides with
/// `@Setting`. Conforming directly costs one registrar and the two forwarding
/// methods below, and nothing is lost — there are no stored settings for
/// `@Observable` to manage.
///
/// Settings that belong to a single server connection do not live here — those
/// are stored with the connection in the database.
@MainActor
public final class AppSettings: Observable {
  public static let shared = AppSettings()

  private let store: SettingsStore
  private let registrar = ObservationRegistrar()

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

  nonisolated func access<Member>(keyPath: KeyPath<AppSettings, Member>) {
    registrar.access(self, keyPath: keyPath)
  }

  nonisolated func withMutation<Member, Result>(
    keyPath: KeyPath<AppSettings, Member>, _ mutation: () throws -> Result
  ) rethrows -> Result {
    try registrar.withMutation(of: self, keyPath: keyPath, mutation)
  }

  @Setting(.documentDeleteConfirmation)
  public var documentDeleteConfirmation: Bool

  @Setting(.enableBiometricAppLock)
  public var enableBiometricAppLock: Bool

  @Setting(.defaultSearchMode)
  public var defaultSearchMode: FilterState.SearchMode

  @Setting(.defaultSortField)
  public var defaultSortField: SortField

  @Setting(.defaultSortOrder)
  public var defaultSortOrder: DataModel.SortOrder

  @Setting(.filterBarConfiguration)
  public var filterBarConfiguration: FilterBarConfiguration

  @Setting(.currentAppVersion)
  public var currentAppVersion: AppVersion?

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
