//
//  Keychain.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.04.23.
//

import Foundation
import os

public enum Keychain {
    public enum KeychainError: Error {
        case duplicateItem
        case itemNotFound
        case invalidItemFormat
        case unexpectedStatus(OSStatus)
        case identitySaveFailed(OSStatus)
        case identityDeleteFailed(OSStatus)
        case identityReadFailed(OSStatus)
    }

    public static func save(service: String, account: String, value: Data) throws(KeychainError) {
        let query: [String: Any] = [
            kSecValueData as String: value,
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            throw .duplicateItem
        }

        guard status == errSecSuccess else {
            throw .unexpectedStatus(status)
        }
    }

    public static func update(service: String, account: String, value: Data) throws(KeychainError) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let update = [kSecValueData: value] as CFDictionary
        let status = SecItemUpdate(query as CFDictionary, update)

        guard status != errSecItemNotFound else {
            throw .itemNotFound
        }

        guard status == errSecSuccess else {
            throw .unexpectedStatus(status)
        }
    }

    public static func saveOrUpdate(service: String, account: String, value: Data) throws(KeychainError) {
        do {
            try save(service: service, account: account,
                     value: value)
        } catch .duplicateItem {
            try update(service: service, account: account,
                       value: value)
        }
    }

    public static func read(service: String, account: String) throws(KeychainError) -> Data? {
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
            return nil
        }

        guard status == errSecSuccess else {
            throw .unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw .invalidItemFormat
        }

        return data
    }

    public static func delete(service: String, account: String) throws(KeychainError) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess else {
            throw .unexpectedStatus(status)
        }
    }

    public static func saveIdentity(identity: SecIdentity?, name: String) throws(KeychainError) {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecValueRef as String: identity as Any,
            kSecAttrLabel as String: name,
        ]
        let res = SecItemAdd(attributes as CFDictionary, nil)
        if res == noErr {
            Logger.common.info("Identity saved successfully in the keychain")
        } else {
            Logger.common.warning("Something went wrong trying to save the Identity in the keychain")
            throw .identitySaveFailed(res)
        }
    }

    public static func readAllIdentities() throws(KeychainError) -> [(SecIdentity, String)] {
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
            Logger.common.info("No identities found in keychain")
        } else {
            Logger.common.warning("Error reading keychain identities: \(res)")
            throw .identityReadFailed(res)
        }

        return ret
    }

    public static func readIdentity(name: String) -> SecIdentity? {
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
            Logger.common.warning("Something went wrong trying to find the identity in the keychain")
        }
        return nil
    }

    public static func deleteIdentity(name: String) throws(KeychainError) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: name,
        ]

        let res = SecItemDelete(query as CFDictionary)
        if res == noErr {
            Logger.common.info("Successfully deleted the identity")
        } else {
            Logger.common.warning("Error deleting the identity")
            throw .identityDeleteFailed(res)
        }
    }
}
