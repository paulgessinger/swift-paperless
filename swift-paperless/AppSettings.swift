//
//  SettingsKeys.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.08.23.
//
import Combine
import Foundation
import os
import SwiftUI

enum SettingsKeys: String {
    case documentDeleteConfirmation
    case enableBiometricAppLock
    case defaultSearchMode
    case defaultSortField
    case defaultSortOrder

    case editingUserInterfaceExperiment
}

@MainActor
class AppSettings: ObservableObject {
    private static let appVersionKey = "currentAppVersion"
    private init() {
        let lastVersion: Version?
        do {
            lastVersion = try UserDefaults.standard.load(Version.self, key: Self.appVersionKey)
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

        guard let currentVersion = Version(release: release!, build: build!) else {
            return
        }

        Logger.shared.info("Current app version is: \(currentVersion, privacy: .public)")

        do {
            try UserDefaults.standard.store(currentVersion, key: Self.appVersionKey)
        } catch {
            Logger.shared.error("Unable to store current version (\(String(describing: currentVersion), privacy: .public): \(error)")
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
    var defaultSortOrder = SortOrder.descending

    enum EditingUserInterface: Codable, CaseIterable {
        case automatic, v1, v2, v3
    }

    @PublishedUserDefaultsBacked(.editingUserInterfaceExperiment)
    var editingUserInterface: EditingUserInterface = .automatic

    struct Version: CustomStringConvertible, Codable, Equatable {
        private let releaseStored: [UInt]

        let build: UInt

        enum CodingKeys: String, CodingKey {
            case releaseStored = "release"
            case build
        }

        init?(release: String, build: String) {
            releaseStored = release.split(separator: ".").compactMap { UInt($0) }
            guard releaseStored.count == 3 else {
                return nil
            }
            guard let build = UInt(build) else {
                return nil
            }
            self.build = build
        }

        init(release: (UInt, UInt, UInt), build: UInt) {
            releaseStored = [release.0, release.1, release.2]
            self.build = build
        }

        var release: (UInt, UInt, UInt) {
            precondition(releaseStored.count == 3)
            return (releaseStored[0], releaseStored[1], releaseStored[2])
        }

        var releaseString: String {
            precondition(releaseStored.count == 3)
            return releaseStored.map { String($0) }.joined(separator: ".")
        }

        var description: String {
            "\(releaseStored.map { String($0) }.joined(separator: ".")) (\(build))"
        }
    }

    var lastAppVersion: Version?
    @UserDefaultsBacked(appVersionKey)
    var currentAppVersion: Version? = nil

    func resetAppVersion() {
        Logger.shared.info("Resetting stored app version")
        currentAppVersion = nil
    }

    let settingsChanged = PassthroughSubject<Void, Never>()
}

extension AppSettings {
    nonisolated
    static func value<Value: Codable>(for key: SettingsKeys, or defaultValue: Value) -> Value {
        let key = key.rawValue
        guard let obj = UserDefaults.standard.object(forKey: key) as? Data else {
            return defaultValue
        }
        do {
            let value = try JSONDecoder().decode(Value.self, from: obj)
            Logger.shared.trace("AppSettings.value(\(key, privacy: .public)) value read: \(String(describing: value), privacy: .private)")
            return value
        } catch {
            Logger.shared.error("AppSettings.value(\(key)): unable to decode, returning default value (\(error))")
            return defaultValue
        }
    }
}

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
