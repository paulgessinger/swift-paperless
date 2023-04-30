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

    private let keychainAccount = "PaperlessAccount"

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
        guard let host = apiHost else {
            return nil
        }

        let data: Data
        do {
            data = try Keychain.read(service: host,
                                     account: keychainAccount)
        } catch {
            print(error)
            return nil
        }

        return Connection(host: host, token: String(data: data, encoding: .utf8)!)
    }

    func set(_ conn: Connection) throws {
        apiHost = conn.host

        try Keychain.saveOrUpdate(service: conn.host,
                                  account: keychainAccount,
                                  value: conn.token.data(using: .utf8)!)

        state = .valid
        connection = conn
    }

    func logout() {
        guard let host = apiHost else {
            return
        }

        do {
            try Keychain.delete(service: host,
                                account: keychainAccount)
        } catch {
            print(error)
        }

        connection = nil
        state = .invalid
    }
}
