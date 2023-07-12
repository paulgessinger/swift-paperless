//
//  ConnectionManager.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import AuthenticationServices
import Foundation
import os

enum ConnectionScheme: String, Codable {
    case http
    case https
}

struct Connection: Equatable {
    let host: String
    let token: String
    let extraHeaders: [ConnectionManager.HeaderValue]
    let scheme: ConnectionScheme

    init(host: String, token: String, extraHeaders: [ConnectionManager.HeaderValue] = [], scheme: ConnectionScheme = .https) {
        self.token = token
        self.extraHeaders = extraHeaders

        let pattern = /(?:(https?):\/\/)?(.*)\/?/

        // parse host
        if let match = try? pattern.wholeMatch(in: host) {
            // always take host part
            self.host = String(match.2)
            // if host string did contain a scheme
            if let s = match.1 {
                // if it's valid use it
                if let s = ConnectionScheme(rawValue: String(s)) {
                    self.scheme = s
                } else {
                    // it's not valid, default to argument
                    Logger.shared.error("Unable to convert stored host scheme \(s) to scheme enum. Assuming \(scheme.rawValue)")
                    self.scheme = scheme
                }
            } else {
                // host string did not contain a scheme, take argument
                self.scheme = scheme
            }
        } else {
            // host did not match pattern (weird!) use argument
            Logger.shared.error("Unparsable host given")
            self.host = host
            self.scheme = scheme
        }
    }
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

    @UserDefaultBacked(key: "ConnectionScheme", storage: .group)
    var scheme: ConnectionScheme = .https

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
                          extraHeaders: extraHeaders, scheme: scheme)
    }

    func set(host: String, token: String, scheme: ConnectionScheme) throws {
        apiHost = host
        self.scheme = scheme

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
