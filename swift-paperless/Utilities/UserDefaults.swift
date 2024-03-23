//
//  UserDefaults.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.23.
//

import Foundation
import os

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
            Logger.shared.trace("Getting UserDefaultBacked(\(key))")
            guard let obj = storage.object(forKey: key) as? Data else {
                Logger.shared.trace("UserDefaultBacked(\(key)) not found returning default")
                return defaultValue
            }
            do {
                return try JSONDecoder().decode(Value.self, from: obj)
            } catch {
                Logger.shared.error("UserDefaultBacked(\(key)): unable to decode, returning default value")
                Logger.shared.trace("Stored value: \(String(data: obj, encoding: .utf8) ?? "No value")")
                return defaultValue
            }
        }

        nonmutating set {
            Logger.shared.trace("Setting UserDefaultBacked(\(key, privacy: .public)) to \(String(describing: newValue), privacy: .private)")
            do {
                let data = try JSONEncoder().encode(newValue)
                storage.set(data, forKey: key)
            } catch {
                Logger.shared.error("Unable to set value to UserDefaults for key \(key, privacy: .public), \(error)")
            }
        }
    }

    init(wrappedValue defaultValue: Value, key: String, storage: UserDefaults = .standard) {
        self.key = key
        self.storage = storage
        self.defaultValue = defaultValue
    }
}

// extension UserDefaultBacked where Value: ExpressibleByNilLiteral {
//    init(key: String, storage: UserDefaults = .standard) {
//        self.init(wrappedValue: nil, key: key, storage: storage)
//    }
// }
