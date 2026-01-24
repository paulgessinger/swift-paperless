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

enum SettingsKeys: String {
  case documentDeleteConfirmation
  case enableBiometricAppLock
  case defaultSearchMode
  case defaultSortField
  case defaultSortOrder
  case filterBarConfiguration

  case editingUserInterfaceExperiment

  case showDocumentDetailPropertyBar
}

extension PublishedUserDefaultsBacked {
  convenience init(
    wrappedValue defaultValue: Value, _ key: SettingsKeys, storage: UserDefaults = .standard
  ) {
    self.init(wrappedValue: defaultValue, key.rawValue, storage: storage)
  }
}

@MainActor
class AppSettings: ObservableObject {
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

  static var shared = AppSettings()

  @PublishedUserDefaultsBacked(.documentDeleteConfirmation)
  var documentDeleteConfirmation = true

  @PublishedUserDefaultsBacked(.enableBiometricAppLock)
  var enableBiometricAppLock = false

  @PublishedUserDefaultsBacked(.defaultSearchMode)
  var defaultSearchMode = FilterState.SearchMode.titleContent

  @PublishedUserDefaultsBacked(.defaultSortField)
  var defaultSortField = SortField.added

  @PublishedUserDefaultsBacked(.defaultSortOrder)
  var defaultSortOrder = DataModel.SortOrder.descending

  // @TODO: We need a sentinel here that's just "all defaults"
  @PublishedUserDefaultsBacked(.filterBarConfiguration)
  var filterBarConfiguration = FilterBarComponent.allCases

  enum EditingUserInterface: String, Codable, CaseIterable {
    static var allCases: [AppSettings.EditingUserInterface] {
      [.automatic, .v3]
    }

    case automatic
    case v3

    // deprecated, kept here so decoding works
    @available(*, deprecated)
    case v1, v2
  }

  @PublishedUserDefaultsBacked(.editingUserInterfaceExperiment)
  var editingUserInterface: EditingUserInterface = .automatic

  @PublishedUserDefaultsBacked(.showDocumentDetailPropertyBar)
  var showDocumentDetailPropertyBar: Bool = true

  var lastAppVersion: AppVersion?
  @UserDefaultsBacked(appVersionKey)
  var currentAppVersion: AppVersion? = nil

  func resetAppVersion() {
    Logger.shared.info("Resetting stored app version")
    currentAppVersion = nil
    UserDefaults.standard.synchronize()
  }

  let settingsChanged = PassthroughSubject<Void, Never>()
}

extension AppSettings {
  nonisolated
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

@available(*, deprecated)
@MainActor
@propertyWrapper
class AppSettingsObject: ObservableObject {
  @ObservedObject private var observed = AppSettings.shared

  private var tasks = Set<AnyCancellable>()

  var wrappedValue: AppSettings {
    observed
  }

  var projectedValue: ObservedObject<AppSettings>.Wrapper {
    $observed
  }

  init() {
    observed.objectWillChange
      .sink { _ in
        Logger.shared.debug("AppSettings objectwill change from singleton in wrapper")
        self.objectWillChange.send()
      }
      .store(in: &tasks)
  }
}

@available(*, deprecated)
@MainActor
@propertyWrapper
struct AppSetting<Value: Codable>: DynamicProperty {
  typealias SettingsKeyPath = KeyPath<AppSettings, PublishedUserDefaultsBacked<Value>>
  private var keyPath: SettingsKeyPath

  @State private var value: Value

  var wrappedValue: Value {
    get {
      value
    }
    nonmutating set {
      AppSettings.shared.objectWillChange.send()
      let published = AppSettings.shared[keyPath: self.keyPath]
      published.$backing.wrappedValue = newValue
      value = newValue
      AppSettings.shared.settingsChanged.send()
    }
  }

  var projectedValue: Binding<Value> {
    Binding<Value>(
      get: {
        wrappedValue
      },
      set: { wrappedValue = $0 }
    )
  }

  init(_ keyPath: SettingsKeyPath) {
    self.keyPath = keyPath
    _value = State(initialValue: AppSettings.shared[keyPath: keyPath].$backing.wrappedValue)
  }
}
