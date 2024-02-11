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
    let url: URL
    let token: String
    let extraHeaders: [ConnectionManager.HeaderValue]

    init(url: URL, token: String, extraHeaders: [ConnectionManager.HeaderValue] = [], scheme _: ConnectionScheme = .https) {
        self.url = url
        self.token = token
        self.extraHeaders = extraHeaders
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

    @UserDefaultBacked(key: "ApiPath", storage: .group)
    var apiPath: String? = nil

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
        guard let apiHost, var url = URL(string: apiHost) else {
            return nil
        }

        if let path = apiPath {
            url = url.appending(path: path)
        }

        let data: Data
        do {
            data = try Keychain.read(service: apiHost,
                                     account: keychainAccount)
        } catch {
            return nil
        }

        return Connection(url: url,
                          token: String(data: data, encoding: .utf8)!,
                          extraHeaders: extraHeaders)
    }

    func set(base: URL, token: String) throws {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            Logger.shared.error("Previously ok'ed URL could not be parsed")
            return
        }

        let path = (components.path == "" || components.path == "/") ? nil : components.path
        components.path = ""

        let host = base.absoluteString

        apiHost = host
        apiPath = path

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
            Logger.shared.error("Error logging out: \(error)")
        }

        apiHost = nil
        apiPath = nil

        state = .invalid
    }
}

extension [ConnectionManager.HeaderValue] {
    func apply(toRequest req: inout URLRequest) {
        for kv in self {
            req.setValue(kv.value, forHTTPHeaderField: kv.key)
        }
    }
}
