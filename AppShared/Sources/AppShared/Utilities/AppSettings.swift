//
//  SettingsKeys.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.08.23.
//
import Combine
import Common
import DataModel
import Foundation
import SwiftUI
import os

public enum SettingsKeys: String {
  case documentDeleteConfirmation
  case enableBiometricAppLock
  case defaultSearchMode
  case defaultSortField
  case defaultSortOrder
  case filterBarConfiguration
}

extension PublishedUserDefaultsBacked {
  public convenience init(
    wrappedValue defaultValue: Value, _ key: SettingsKeys, storage: UserDefaults = .standard
  ) {
    self.init(wrappedValue: defaultValue, key.rawValue, storage: storage)
  }
}

@MainActor
public class AppSettings: ObservableObject {
  private static let appVersionKey = "currentAppVersion"
  private init() {
    let lastVersion: AppVersion?
    do {
      lastVersion = try UserDefaults.standard.load(AppVersion.self, key: Self.appVersionKey)
    } catch {
      Logger.shared.error("Last app version could not be read: \(error)")
      lastVersion = nil
    }

    Logger.shared.info("Last app version was: \(lastVersion?.description ?? "?", privacy: .public)")

    lastAppVersion = lastVersion

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

    guard let currentVersion = AppVersion(version: release!, build: build!) else {
      return
    }

    Logger.shared.info("Current app version is: \(currentVersion, privacy: .public)")

    do {
      try UserDefaults.standard.store(currentVersion, key: Self.appVersionKey)
    } catch {
      Logger.shared.error(
        "Unable to store current version (\(String(describing: currentVersion), privacy: .public): \(error)"
      )
    }
  }

  public static var shared = AppSettings()

  @PublishedUserDefaultsBacked(.documentDeleteConfirmation)
  public var documentDeleteConfirmation = true

  @PublishedUserDefaultsBacked(.enableBiometricAppLock)
  public var enableBiometricAppLock = false

  @PublishedUserDefaultsBacked(.defaultSearchMode)
  public var defaultSearchMode = FilterState.SearchMode.titleContent

  @PublishedUserDefaultsBacked(.defaultSortField)
  public var defaultSortField = SortField.added

  @PublishedUserDefaultsBacked(.defaultSortOrder)
  public var defaultSortOrder = DataModel.SortOrder.descending

  // @TODO: We need a sentinel here that's just "all defaults"
  @PublishedUserDefaultsBacked(.filterBarConfiguration)
  public var filterBarConfiguration = FilterBarConfiguration.default

  public var lastAppVersion: AppVersion?
  @UserDefaultsBacked(appVersionKey)
  public var currentAppVersion: AppVersion? = nil

  public func resetAppVersion() {
    Logger.shared.info("Resetting stored app version")
    currentAppVersion = nil
    UserDefaults.standard.synchronize()
  }

  public let settingsChanged = PassthroughSubject<Void, Never>()
}

extension AppSettings {
  public nonisolated
    static func value<Value: Codable>(for key: SettingsKeys, or defaultValue: Value) -> Value
  {
    let key = key.rawValue
    guard let obj = UserDefaults.standard.object(forKey: key) as? Data else {
      return defaultValue
    }
    do {
      let value = try JSONDecoder().decode(Value.self, from: obj)
      Logger.shared.trace(
        "AppSettings.value(\(key, privacy: .public)) value read: \(String(describing: value), privacy: .private)"
      )
      return value
    } catch {
      Logger.shared.error(
        "AppSettings.value(\(key)): unable to decode, returning default value (\(error))")
      return defaultValue
    }
  }
}
