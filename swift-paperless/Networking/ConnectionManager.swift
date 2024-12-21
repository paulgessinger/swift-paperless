//
//  ConnectionManager.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import AuthenticationServices
import Common
import CryptoKit
import DataModel
import Foundation
import os

struct Connection: Equatable {
    let url: URL
    let token: String?
    let extraHeaders: [ConnectionManager.HeaderValue]
    let identity: String?

    init(url: URL, token: String? = nil, extraHeaders: [ConnectionManager.HeaderValue] = [], identityName: String?) {
        self.url = url
        self.token = token
        self.extraHeaders = extraHeaders
        identity = identityName
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

struct StoredConnection: Equatable, Codable, Identifiable {
    var id: UUID = .init()
    var url: URL
    var extraHeaders: [ConnectionManager.HeaderValue]
    var user: User
    var identity: String?

    var token: String? {
        get throws {
            guard let data = try Keychain.read(service: url.absoluteString,
                                               account: user.username)
            else {
                Logger.api.info("Read nil valuefrom keychain, return nil")
                return nil
            }
            let token = String(data: data, encoding: .utf8)!
            // we might have saved empty strings as tokens before, convert to nil when reading
            if token.isEmpty {
                Logger.api.info("Read empty string from keychain, return nil")
                return nil
            }
            return token
        }
    }

    func setToken(_ token: String) throws(Keychain.KeychainError) {
        try Keychain.saveOrUpdate(service: url.absoluteString,
                                  account: user.username,
                                  value: token.data(using: .utf8)!)
    }

    var connection: Connection {
        get throws {
            try Connection(url: url, token: token, extraHeaders: extraHeaders, identityName: identity)
        }
    }

    var fullLabel: String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.api.error("Valid stored connection's URL could not be decomposed")
            return "\(user.username)@\(url)"
        }
        components.user = user.username
        guard let urlString = components.url?.absoluteString else {
            Logger.api.error("Decomposed URL could not be reformed")
            return "\(user.username)@\(url)"
        }
        return urlString
    }

    var label: String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.api.error("Valid stored connection's URL could not be decomposed")
            return "\(user.username)@\(url)"
        }

        guard var urlString = components.host else {
            return "\(user.username)@\(url)"
        }

        if components.path != "" {
            if urlString.last != "/", components.path.first != "/" {
                urlString += "/"
            }
            urlString += "\(components.path)"
        }
        return "\(user.username)@\(urlString)"
    }

    var shortLabel: String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.api.error("Valid stored connection's URL could not be decomposed")
            return "\(user.username)@\(url)"
        }
        guard var urlString = components.host else {
            return "\(user.username)@\(url)"
        }

        if let scheme = components.scheme {
            urlString = "\(scheme)://\(urlString)"
        }

        if let port = components.port, port != 80, port != 443 {
            urlString = "\(urlString):\(port)"
        }

        if components.path != "" {
            if urlString.last != "/", components.path.first != "/" {
                urlString += "/"
            }
            urlString += "\(components.path)"
        }
        return urlString
    }

    var redactedLabel: String {
        #if DEBUG
            return fullLabel
        #else
            let pid = ProcessInfo.processInfo.processIdentifier

            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                Logger.api.error("Valid stored connection's URL could not be decomposed")
                return "<unavailable>"
            }

            let userHash = SHA256.hash(data: "\(pid)\(user.username)".data(using: .utf8)!).compactMap { String(format: "%02x", $0) }.joined().prefix(8)
            let urlHash = SHA256.hash(data: "\(pid)\(url)".data(using: .utf8)!).compactMap { String(format: "%02x", $0) }.joined().prefix(8)

            components.user = "user-\(userHash)"
            components.host = "\(urlHash).example.com"
            guard let result = components.url else {
                Logger.api.error("Decomposed URL could not be reformed")
                return "<unavailable>"
            }

            return result.absoluteString
        #endif
    }
}

@MainActor
class ConnectionManager: ObservableObject {
    struct HeaderValue: Codable, Equatable {
        // @TODO: (multi-server) Replace with direct field
        private var _id: UUID?
        var key: String
        var value: String

        var id: UUID {
            get { _id ?? UUID() }
            set { _id = newValue }
        }

        enum CodingKeys: String, CodingKey {
            case _id = "id"
            case key, value
        }

        init(key: String, value: String) {
            _id = UUID()
            self.key = key
            self.value = value
        }
    }

    let previewMode: Bool

    init(previewMode: Bool? = nil) {
        if let previewMode {
            self.previewMode = previewMode
        } else {
            self.previewMode = UserDefaults.standard.bool(forKey: "PreviewMode")
        }
    }

    // @TODO: (multi-server) Remove in a few versions
    @UserDefaultsBacked("ExtraHeaders", storage: .group)
    private var extraHeaders: [HeaderValue] = []

    // @TODO: (multi-server) Remove in a few versions
    private var apiHost: String? {
        get {
            UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")?.string(forKey: "ApiHost")
        }
        set {
            UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")?.set(newValue, forKey: "ApiHost")
        }
    }

    // @TODO: (multi-server) Remove in a few versions
    @UserDefaultsBacked("ApiPath", storage: .group)
    private var apiPath: String? = nil

    @UserDefaultsBacked("Connections", storage: .group)
    private(set) var connections: [UUID: StoredConnection] = [:] {
        willSet {
            objectWillChange.send()
        }
    }

    @UserDefaultsBacked("ActiveConnectionId", storage: .group)
    var activeConnectionId: UUID? = nil {
        willSet {
            objectWillChange.send()
        }
    }

    func isServerUnique(_ url: URL) -> Bool {
        let allUrls = connections.values.map(\.url.absoluteString)
        let url = url.absoluteString
        return allUrls.reduce(0) { $1 == url ? $0 + 1 : $0 } == 1
    }

    func migrateToMultiServer() async {
        Logger.migration.trace("Checking migration status")
        if activeConnectionId == nil, apiHost != nil {
            Logger.migration.info("Connection manager has prior connection: migrating to multi-server scheme")

            guard let connection else {
                Logger.migration.warning("Existing connection was invalid")
                return
            }

            let repository = await ApiRepository(connection: connection)

            // Migration runs asynchronously, this should be fine, since the active connection in memory
            // will stay valid while we're trying.
            Task {
                Logger.migration.info("Getting current user to populate newly stored connection")
                do {
                    let currentUser = try await repository.currentUser()
                    Logger.migration.info("Got current user: \(String(describing: currentUser))")

                    let newConnection = StoredConnection(url: connection.url, extraHeaders: connection.extraHeaders, user: currentUser)
                    Logger.migration.info("Connection to store is: \(String(describing: newConnection))")

                    connections[newConnection.id] = newConnection
                    activeConnectionId = newConnection.id
                } catch {
                    Logger.migration.error("An error was encountered: \(error)")
                }
            }
        } else {
            Logger.migration.info("Skipping migration")
        }
    }

    var connection: Connection? {
        // @TODO: Downgrade these logs back to debug
        Logger.api.info("Making connection object")

        if previewMode {
            Logger.api.info("Running in preview mode")
            let udef = UserDefaults.standard
            let url = URL(string: udef.string(forKey: "PreviewURL") ?? "https://paperless.example.com/api/")!
            let token = udef.string(forKey: "PreviewToken") ?? "pseudo-token-that-will-not-work"
            return Connection(url: url,
                              token: token,
                              extraHeaders: extraHeaders, identityName: nil)
        }

        if let activeConnectionId, let storedConnection = connections[activeConnectionId] {
            Logger.api.info("Have valid multi-server connection info: \(storedConnection.redactedLabel, privacy: .public)")
            do {
                return try storedConnection.connection
            } catch {
                Logger.api.error("Getting connection from stored connection: \(storedConnection.redactedLabel, privacy: .public)")
            }
        }

        // @TODO: (multi-server) Remove in a few versions
        Logger.api.info("Making compatibility connection from parts (OLD STORAGE FLOW)")

        guard let apiHost, var url = URL(string: apiHost) else {
            return nil
        }

        if let path = apiPath {
            url = url.appending(path: path)
        }

        let token: String?
        do {
            let keychainAccount = "PaperlessAccount"
            let data = try Keychain.read(service: apiHost,
                                         account: keychainAccount)
            if let data {
                token = String(data: data, encoding: .utf8)!
            } else {
                token = nil
            }
        } catch {
            return nil
        }

        return Connection(url: url,
                          token: token,
                          extraHeaders: extraHeaders, identityName: nil)
    }

    var storedConnection: StoredConnection? {
        if previewMode {
            Logger.api.info("Running in preview mode")
            let url = URL(string: UserDefaults.standard.string(forKey: "PreviewURL") ?? "https://paperless.example.com/api/")!
            return StoredConnection(url: url,
                                    extraHeaders: extraHeaders,
                                    user: User(id: 1, isSuperUser: true, username: "paperless"))
        }

        guard let activeConnectionId, let stored = connections[activeConnectionId] else {
            return nil
        }
        return stored
    }

    func login(_ connection: StoredConnection) {
        Logger.api.info("Performing login for connection with ID \(connection.id, privacy: .private(mask: .hash))")
        connections[connection.id] = connection
        activeConnectionId = connection.id
    }

    func setExtraHeaders(_ headers: [HeaderValue]) {
        guard let activeConnectionId, var stored = connections[activeConnectionId] else {
            Logger.api.warning("Tried to set extra headers but have no active connection (?)")
            return
        }
        Logger.api.trace("Updating extra headers in \(stored.id) to \(headers)")
        stored.extraHeaders = headers
        connections[stored.id] = stored
    }

    func logout() {
        Logger.api.info("Requested logout from current server")

        // @TODO: (multi-server) Remove in a few versions
        if let host = apiHost {
            Logger.api.info("Prior single-server connection present, clearing")
            do {
                let keychainAccount = "PaperlessAccount"
                try Keychain.delete(service: host,
                                    account: keychainAccount)
            } catch {
                Logger.shared.error("Error logging out: \(error)")
            }

            apiHost = nil
            apiPath = nil
        }

        if let activeConnectionId, let storedConnection = connections[activeConnectionId] {
            Logger.api.info("Have active connection \(storedConnection.redactedLabel, privacy: .public)")
            Logger.api.info("Clearing connection with ID \(activeConnectionId)")
            connections.removeValue(forKey: activeConnectionId)
            let count = connections.count
            Logger.api.info("Have \(count)")
            if let newConn = connections.first?.value {
                Logger.api.info("Setting connection to \(newConn.id)")
                self.activeConnectionId = newConn.id
            } else {
                Logger.api.info("Setting active connection to nil")
                self.activeConnectionId = nil
            }
        }
    }
}

extension [ConnectionManager.HeaderValue] {
    func apply(toRequest req: inout URLRequest) {
        for kv in self {
            if kv.key.contains(" ") || kv.key.isEmpty { continue }
            req.setValue(kv.value, forHTTPHeaderField: kv.key)
        }
    }
}
