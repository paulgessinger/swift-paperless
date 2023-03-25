//
//  ConnectionManager.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import AuthenticationServices
import Foundation

struct Connection: Equatable {
    let host: String
    let token: String
}

class ConnectionManager: ObservableObject {
    enum LoginState {
        case none
        case valid
        case invalid
    }

    enum ConnectionError: Error {
        case keychain
    }

    @Published var state: LoginState = .none
    @Published var connection: Connection?

    private(set) var apiHost: String? {
        get {
            UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")!.string(forKey: "ApiHost")
        }
        set {
            UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")!.set(newValue, forKey: "ApiHost")
        }
    }

    func check() async {
        await MainActor.run {
            guard let conn = get() else {
                state = .invalid
                return
            }

            connection = conn
            state = .valid
        }
    }

    func get() -> Connection? {
//        print("getting")

        guard let host = apiHost else {
            return nil
        }

        let query = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrAccount: "",
            kSecAttrServer: host,
            kSecReturnData: true,
        ] as CFDictionary

        var result: AnyObject?
        SecItemCopyMatching(query, &result)
        guard let data = result as? Data else {
            return nil
        }

        return Connection(host: host, token: String(data: data, encoding: .utf8)!)
    }

    func set(_ conn: Connection) throws {
//        print("setting")
        apiHost = conn.host

        let query = [
            kSecValueData: conn.token.data(using: .utf8)!,
            kSecClass: kSecClassInternetPassword,
            kSecAttrAccount: "",
            kSecAttrServer: conn.host,
        ] as CFDictionary

        let status = SecItemAdd(query, nil)

        if status == errSecSuccess {
            state = .valid
            connection = conn
            return
        }

        if status == errSecDuplicateItem {
            let query = [
                kSecClass: kSecClassInternetPassword,
                kSecAttrServer: conn.host,
                kSecAttrAccount: "",
            ] as CFDictionary

            let update = [kSecValueData: conn.token.data(using: .utf8)!] as CFDictionary
            SecItemUpdate(query, update)
        }
        else {
            throw ConnectionError.keychain
        }
    }

    func logout() {
        guard let host = apiHost else {
            return
        }

        let query = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: host,
            kSecAttrAccount: "",
        ] as CFDictionary

        SecItemDelete(query)

        connection = nil
        state = .invalid
    }
}
