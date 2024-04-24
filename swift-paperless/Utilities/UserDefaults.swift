//
//  UserDefaults.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.23.
//

import Foundation
import os

#if swift(>=6.0)
    #warning("Reevaluate whether this decoration is necessary.")
#endif
private nonisolated(unsafe)
let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserDefaults")

extension UserDefaults {
    static let group = UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")!
}

// https://www.swiftbysundell.com/articles/property-wrappers-in-swift/

@propertyWrapper
struct UserDefaultBacked<Value> where Value: Codable {
    private let key: String
    private let storage: UserDefaults
    private let defaultValue: Value

    var wrappedValue: Value {
        get {
            logger.trace("Getting UserDefaultBacked(\(key))")
            guard let obj = storage.object(forKey: key) as? Data else {
                Logger.shared.trace("UserDefaultBacked(\(key)) not found returning default")
                return defaultValue
            }
            do {
                let value = try JSONDecoder().decode(Value.self, from: obj)
                logger.trace("UserDefaultBacked(\(key, privacy: .public)) value read: \(String(describing: value), privacy: .private)")
                return value
            } catch {
                logger.error("UserDefaultBacked(\(key)): unable to decode, returning default value (\(error))")
                logger.trace("Stored value: \(String(data: obj, encoding: .utf8) ?? "No value")")
                return defaultValue
            }
        }

        nonmutating set {
            logger.trace("Setting UserDefaultBacked(\(key, privacy: .public)) to \(String(describing: newValue), privacy: .private)")
            do {
                let data = try JSONEncoder().encode(newValue)
                storage.set(data, forKey: key)
            } catch {
                logger.error("Unable to set value to UserDefaults for key \(key, privacy: .public), \(error)")
            }
        }
    }

    init(wrappedValue defaultValue: Value, key: String, storage: UserDefaults = .standard) {
        self.key = key
        self.storage = storage
        self.defaultValue = defaultValue
    }
}

@propertyWrapper
class PublishedUserDefaultBacked<Value> where Value: Codable {
    @UserDefaultBacked
    var backing: Value
//    var backing: UserDefaultBacked<Value>

    @Published var wrappedValue: Value {
        didSet {
            backing = wrappedValue
        }
    }

    init(wrappedValue defaultValue: Value, key: String, storage: UserDefaults = .standard) {
        _backing = .init(wrappedValue: defaultValue, key: key, storage: storage)
        wrappedValue = _backing.wrappedValue
    }
}
