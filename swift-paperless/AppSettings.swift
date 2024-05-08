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
}

@MainActor
class AppSettings: ObservableObject {
    private init() {}

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

    let settingsChanged = PassthroughSubject<Void, Never>()
}

extension AppSettings {
    nonisolated
    static func value<Value: Codable>(for key: SettingsKeys, or defaultValue: Value) -> Value {
        let key = key.rawValue
        guard let obj = UserDefaults.standard.object(forKey: key) as? Data else {
            Logger.shared.trace("AppSettings.value(\(key)) not found returning default")
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
