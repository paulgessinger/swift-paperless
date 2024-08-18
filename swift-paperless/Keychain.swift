//
//  Keychain.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.04.23.
//

import Foundation
import os

enum Keychain {
    enum KeychainError: Error {
        case duplicateItem
        case itemNotFound
        case invalidItemFormat
        case unexpectedStatus(OSStatus)
        case identitySaveFailed(OSStatus)
        case identityDeleteFailed(OSStatus)
        case identityReadFailed(OSStatus)
    }

    static func save(service: String, account: String, value: Data) throws {
        let query: [String: Any] = [
            kSecValueData as String: value,
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            throw KeychainError.duplicateItem
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func update(service: String, account: String, value: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let update = [kSecValueData: value] as CFDictionary
        let status = SecItemUpdate(query as CFDictionary, update)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func saveOrUpdate(service: String, account: String, value: Data) throws {
        do {
            try save(service: service, account: account,
                     value: value)
        } catch KeychainError.duplicateItem {
            try update(service: service, account: account,
                       value: value)
        }
    }

    static func read(service: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
//            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary,
                                         &result)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidItemFormat
        }

        return data
    }

    static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func saveIdentity(identity: SecIdentity?, name: String) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecValueRef as String: identity as Any,
            kSecAttrLabel as String: name,
        ]
        let res = SecItemAdd(attributes as CFDictionary, nil)
        if res == noErr {
            Logger.shared.info("Identity saved successfully in the keychain")
        } else {
            Logger.shared.warning("Something went wrong trying to save the Identity in the keychain")
            throw KeychainError.identitySaveFailed(res)
        }
    }

    static func readAllIdentities() throws -> [(SecIdentity, String)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnRef as String: kCFBooleanTrue as Any,
        ]
        var item_ref: CFTypeRef?

        var ret: [(SecIdentity, String)] = []
        let res = SecItemCopyMatching(query as CFDictionary, &item_ref)
        if res == noErr {
            let items = item_ref as! [[String: Any]]
            for item in items {
                let name = item[kSecAttrLabel as String] as? String
                let optionalIdentity = item[kSecValueRef as String] as! SecIdentity?
                if let identity = optionalIdentity {
                    ret.append((identity, name!))
                }
            }
        } else if res == errSecItemNotFound {
            Logger.shared.info("No identities found in keychain")
        } else {
            Logger.shared.warning("Error reading keychain identities: \(res)")
            throw KeychainError.identityReadFailed(res)
        }

        return ret
    }

    static func readIdentity(name: String) -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecAttrLabel as String: name,
            kSecReturnRef as String: kCFBooleanTrue as Any,
        ]
        var item_ref: CFTypeRef?

        if SecItemCopyMatching(query as CFDictionary, &item_ref) == noErr {
            if let existingItem = item_ref as? [String: Any],
               let _ = existingItem[kSecAttrLabel as String] as? String
            {
                let identity = existingItem[kSecValueRef as String] as! SecIdentity?
                return identity
            }
        } else {
            Logger.shared.warning("Something went wrong trying to find the identity in the keychain")
        }
        return nil
    }

    static func deleteIdentity(name: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: name,
        ]

        let res = SecItemDelete(query as CFDictionary)
        if res == noErr {
            Logger.shared.info("Successfully deleted the identity")
        } else {
            Logger.shared.warning("Error deleting the identity")
            throw KeychainError.identityDeleteFailed(res)
        }
    }
}
