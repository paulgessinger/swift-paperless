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
    let extraHeaders: [ConnectionManager.HeaderValue]
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
//    @Published var connection: Connection?

    private let keychainAccount = "PaperlessAccount"

    struct HeaderValue: Codable, Equatable {
        var key: String
        var value: String
    }

    @UserDefaultBacked(key: "ExtraHeaders", storage: .group)
    var extraHeaders: [HeaderValue] = []

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
            guard connection != nil else {
                state = .invalid
                return
            }

            state = .valid
        }
    }

    var connection: Connection? {
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

        return Connection(host: host,
                          token: String(data: data, encoding: .utf8)!,
                          extraHeaders: extraHeaders)
    }

    func set(host: String, token: String) throws {
        apiHost = host

        try Keychain.saveOrUpdate(service: host,
                                  account: keychainAccount,
                                  value: token.data(using: .utf8)!)

        state = .valid
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

        state = .invalid
    }
}

extension Array where Element == ConnectionManager.HeaderValue {
    func apply(toRequest req: inout URLRequest) {
        for kv in self {
            req.setValue(kv.value, forHTTPHeaderField: kv.key)
        }
    }
}
