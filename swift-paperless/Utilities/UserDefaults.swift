//
//  UserDefaults.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.23.
//

import Combine
import Foundation
import os

let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserDefaults")

extension UserDefaults {
    @MainActor
    static let group = UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")!

    func load<Value>(_: Value.Type, key: String, storage: UserDefaults = .standard) throws -> Value? where Value: Decodable {
        guard let obj = storage.object(forKey: key) as? Data else {
            logger.trace("UserDefaultsBacked(\(key)) not found returning default")
            return nil
        }
        return try JSONDecoder().decode(Value.self, from: obj)
    }

    func store(_ value: some Encodable, key: String, storage: UserDefaults = .standard) throws {
        let data = try JSONEncoder().encode(value)
        storage.set(data, forKey: key)
    }
}

// https://www.swiftbysundell.com/articles/property-wrappers-in-swift/

@propertyWrapper
class UserDefaultsBacked<Value> where Value: Codable {
    let key: String
    private let storage: UserDefaults
    private let defaultValue: Value
    private var cachedValue: Value?

    var wrappedValue: Value {
        get {
            let key = key
            if let cachedValue {
                return cachedValue
            }
            guard let obj = storage.object(forKey: key) as? Data else {
                logger.trace("UserDefaultsBacked(\(key)) not found returning default")
                cachedValue = defaultValue
                return defaultValue
            }
            do {
                let value = try JSONDecoder().decode(Value.self, from: obj)
                logger.trace("UserDefaultsBacked(\(key, privacy: .public)) value read: \(String(describing: value), privacy: .private)")
                cachedValue = value
                return value
            } catch {
                logger.error("UserDefaultsBacked(\(key)): unable to decode, returning default value (\(error))")
                logger.trace("Stored value: \(String(data: obj, encoding: .utf8) ?? "No value")")
                return defaultValue
            }
        }

        set {
            let key = key
            logger.trace("Setting UserDefaultsBacked(\(key, privacy: .public)) to \(String(describing: newValue), privacy: .private)")
            do {
                let data = try JSONEncoder().encode(newValue)
                storage.set(data, forKey: key)
                cachedValue = newValue
            } catch {
                logger.error("Unable to set value to UserDefaults for key \(key, privacy: .public), \(error)")
            }
        }
    }

    var projectedValue: UserDefaultsBacked<Value> { self }

    init(wrappedValue defaultValue: Value, _ key: String, storage: UserDefaults = .standard) {
        self.key = key
        self.storage = storage
        self.defaultValue = defaultValue
    }
}

@propertyWrapper
//    var backing: UserDefaultBacked<Value>
class PublishedUserDefaultsBacked<Value> where Value: Codable {
    static subscript<T: ObservableObject>(
        _enclosingInstance instance: T,
        wrapped _: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, PublishedUserDefaultsBacked<Value>>
    ) -> Value {
        get {
            instance[keyPath: storageKeyPath].backing
        }
        set {
            if let publisher = instance.objectWillChange as? ObservableObjectPublisher {
                publisher.send()
            } else {
                Logger.shared.warning("objectWillChange was not ObservableObjectPublisher but \(String(describing: instance.objectWillChange))")
            }
            instance[keyPath: storageKeyPath].backing = newValue
        }
    }

    @UserDefaultsBacked
    private(set) var backing: Value

    var key: String { $backing.key }

    @available(*, unavailable,
               message: "Can only be applied to classes")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    var projectedValue: PublishedUserDefaultsBacked<Value> { self }

    init(wrappedValue defaultValue: Value, _ key: String, storage: UserDefaults = .standard) {
        _backing = .init(wrappedValue: defaultValue, key, storage: storage)
    }

    init(wrappedValue defaultValue: Value, _ key: SettingsKeys, storage: UserDefaults = .standard) {
        _backing = .init(wrappedValue: defaultValue, key.rawValue, storage: storage)
    }
}
