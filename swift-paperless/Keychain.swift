//
//  Keychain.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.04.23.
//

import Foundation

enum Keychain {
    enum KeychainError: Error {
        case duplicateItem
        case itemNotFound
        case invalidItemFormat
        case unexpectedStatus(OSStatus)
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
    
    static func saveIdentity(identity: SecIdentity?, name: String) {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecValueRef as String: identity,
            kSecAttrLabel as String: name
        ]
        let res = SecItemAdd(attributes as CFDictionary, nil)
        if res == noErr {
            print("Identity saved successfully in the keychain")
        } else {
            print(res)
            print("Something went wrong trying to save the Identity in the keychain")
        }
    }
    
    static func readAllIdenties() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        var item_ref: CFTypeRef?
        
        
        if SecItemCopyMatching(query as CFDictionary, &item_ref) == noErr {
            let items = item_ref as! Array<Dictionary<String, Any>>
            for item in items {
                print(item[kSecAttrLabel as String] as? String)
            }
        } else {
            print("Something went wrong trying to find the idenities in the keychain")
        }
    }
    
    static func readIdentity(name: String) -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecAttrLabel as String: name,
            kSecReturnRef as String: kCFBooleanTrue
        ]
        var item_ref: CFTypeRef?
        
        
        if SecItemCopyMatching(query as CFDictionary, &item_ref) == noErr {
            
            if let existingItem = item_ref as? [String: Any],
               let name = existingItem[kSecAttrLabel as String] as? String
            
            {
                print(name)
                
                let identity = existingItem[kSecValueRef as String] as! SecIdentity?
                return identity
            }
             print("Key err")
        } else {
            print("Something went wrong trying to find the user in the keychain")
        }
        return nil
    }
}
