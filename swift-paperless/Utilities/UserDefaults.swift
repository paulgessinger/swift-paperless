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
            guard let obj = storage.object(forKey: key) as? Data else {
                return defaultValue
            }
            guard let value = try? JSONDecoder().decode(Value.self, from: obj) else {
                return defaultValue
            }

            return value
        }

        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                Logger.shared.error("Unable to set value to UserDefaults for key \(key, privacy: .public)")
                return
            }
            storage.set(data, forKey: key)
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
