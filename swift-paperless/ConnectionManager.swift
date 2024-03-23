//
//  ConnectionManager.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import AuthenticationServices
import Foundation
import os

struct Connection: Equatable {
    let url: URL
    let token: String
    let extraHeaders: [ConnectionManager.HeaderValue]

    init(url: URL, token: String, extraHeaders: [ConnectionManager.HeaderValue] = []) {
        self.url = url
        self.token = token
        self.extraHeaders = extraHeaders
    }

    var scheme: String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.api.error("Unable to decompose connection URL for scheme, returning https")
            return "https"
        }
        guard let scheme = components.scheme else {
            Logger.api.error("Connection URL does not have scheme, returning https")
            return "https"
        }

        return scheme
    }
}

struct StoredConnection: Codable {
    let url: URL
    let extraHeaders: [ConnectionManager.HeaderValue]
    let label: String
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

    private let keychainAccount = "PaperlessAccount"

    struct HeaderValue: Codable, Equatable {
        var id: UUID
        var key: String
        var value: String

        init(key: String, value: String) {
            id = .init()
            self.key = key
            self.value = value
        }
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

    // @TODO: Remove in a few versions
    @UserDefaultBacked(key: "ApiPath", storage: .group)
    var apiPath: String? = nil

    @UserDefaultBacked(key: "ApiPaths", storage: .group)
    var apiPaths: [String] = []

    @UserDefaultBacked(key: "ActiveApiPath", storage: .group)
    var activeApiPath: String? = nil

    init() {
        if let apiPath {
            Logger.shared.notice("Connection manager has ApiPath UserDefault: migrating to multi-server scheme")
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
