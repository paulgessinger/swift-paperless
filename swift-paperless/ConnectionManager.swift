//
//  ConnectionManager.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import AuthenticationServices
import CryptoKit
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

struct StoredConnection: Equatable, Codable, Identifiable {
    var id: UUID = .init()
    var url: URL
    var extraHeaders: [ConnectionManager.HeaderValue]
    var user: User

    var token: String {
        get throws {
            let data = try Keychain.read(service: url.absoluteString,
                                         account: user.username)
            return String(data: data, encoding: .utf8)!
        }
    }

    func setToken(_ token: String) throws {
        try Keychain.saveOrUpdate(service: url.absoluteString,
                                  account: user.username,
                                  value: token.data(using: .utf8)!)
    }

    var connection: Connection {
        get throws {
            try Connection(url: url, token: token, extraHeaders: extraHeaders)
        }
    }

    var label: String {
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

    var redactedLabel: String {
        #if DEBUG
            return label
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

    // @TODO: (multi-server) Remove in a few versions
    @UserDefaultBacked(key: "ExtraHeaders", storage: .group)
    private var extraHeaders: [HeaderValue] = []

    // @TODO: (multi-server) Remove in a few versions
    private var apiHost: String? {
        get {
            UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")!.string(forKey: "ApiHost")
        }
        set {
            UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")!.set(newValue, forKey: "ApiHost")
        }
    }

    // @TODO: (multi-server) Remove in a few versions
    @UserDefaultBacked(key: "ApiPath", storage: .group)
    private var apiPath: String? = nil

    @UserDefaultBacked(key: "Connections", storage: .group)
    private(set) var connections: [UUID: StoredConnection] = [:] {
        willSet {
            objectWillChange.send()
        }
    }

    @UserDefaultBacked(key: "ActiveConnectionId", storage: .group)
    var activeConnectionId: UUID? = nil {
        willSet {
            objectWillChange.send()
        }
    }

    func migrateToMultiServer() async {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "MultiServerMigration")
        logger.trace("Checking migration status")
        if activeConnectionId == nil, apiHost != nil {
            logger.info("Connection manager has prior connection: migrating to multi-server scheme")

            guard let connection else {
                logger.warning("Existing connection was invalid")
                return
            }

            let repository = ApiRepository(connection: connection)
            // Migration runs asynchronously, this should be fine, since the active connection in memory
            // will stay valid while we're trying.
            Task {
                logger.info("Getting current user to populate newly stored connection")
                do {
                    let currentUser = try await repository.currentUser()
                    logger.info("Got current user: \(String(describing: currentUser))")

                    let newConnection = StoredConnection(url: connection.url, extraHeaders: connection.extraHeaders, user: currentUser)
                    logger.info("Connection to store is: \(String(describing: newConnection))")

                    await MainActor.run {
                        connections[newConnection.id] = newConnection
                        activeConnectionId = newConnection.id
                    }
                } catch {
                    logger.error("An error was encountered: \(error)")
                }
            }
        } else {
            logger.info("Skipping migration")
        }
    }

    var connection: Connection? {
        Logger.api.debug("Making connection object")
        if let activeConnectionId, let storedConnection = connections[activeConnectionId] {
            Logger.api.debug("Have valid multi-server connection info: \(storedConnection.redactedLabel, privacy: .public)")
            do {
                return try storedConnection.connection
            } catch {
                Logger.api.error("Getting connection from stored connection: \(storedConnection.redactedLabel, privacy: .public)")
            }
        }

        // @TODO: (multi-server) Remove in a few versions
        Logger.api.debug("Making compatibility connection from parts")

        guard let apiHost, var url = URL(string: apiHost) else {
            return nil
        }

        if let path = apiPath {
            url = url.appending(path: path)
        }

        let data: Data
        do {
            let keychainAccount = "PaperlessAccount"
            data = try Keychain.read(service: apiHost,
                                     account: keychainAccount)
        } catch {
            return nil
        }

        return Connection(url: url,
                          token: String(data: data, encoding: .utf8)!,
                          extraHeaders: extraHeaders)
    }

    var storedConnection: StoredConnection? {
        guard let activeConnectionId, let stored = connections[activeConnectionId] else {
            return nil
        }
        return stored
    }

    func login(_ connection: StoredConnection) throws {
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
