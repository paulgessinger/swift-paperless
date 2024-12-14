//
//  LoginViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 31.07.2024.
//

import Common
import Foundation
import os
import SwiftUI

enum LoginState: Equatable {
    case empty
    case checking
    case valid
    case error(_: LoginError)
}

enum CredentialMode: Equatable, Hashable, CaseIterable {
    case usernameAndPassword
    case token
    case none

    var label: String {
        switch self {
        case .usernameAndPassword:
            String(localized: .login(.credentialModeUsernamePassword))
        case .token:
            String(localized: .login(.credentialModeToken))
        case .none:
            String(localized: .login(.credentialModeNone))
        }
    }

    var description: Text {
        switch self {
        case .usernameAndPassword:
            Text(.login(.credentialModeUsernamePasswordDescription))
        case .token:
            Text(.login(.credentialModeTokenDescription))
        case .none:
            Text(.login(.credentialModeNoneDescription))
        }
    }
}

enum CredentialState: Equatable {
    case none
    case validating
    case valid
    case error(LoginError)
}

@MainActor
@Observable
class LoginViewModel {
    var loginState = LoginState.empty

    var loginStateValid: Bool {
        switch loginState {
        case .valid, .error: // Error is technically not valid, but we want to allow retrying
            true
        default:
            false
        }
    }

    var extraHeaders: [ConnectionManager.HeaderValue] = []

    var selectedIdentity: TLSIdentity?

    var url: String = ""

    var checkUrlTask: Task<Void, Never>?

    enum Scheme: String {
        case http
        case https

        var label: String {
            "\(self)://"
        }
    }

    var scheme = Scheme.https

    var credentialMode = CredentialMode.usernameAndPassword
    var credentialState = CredentialState.none

    // For user password login
    var username: String = ""
    var password: String = ""

    // for token login
    var token: String = ""

    func onChangeUrl(immediate: Bool = false) {
        checkUrlTask?.cancel()
        checkUrlTask = Task {
            loginState = .checking
            if !immediate {
                do {
                    try await Task.sleep(for: .seconds(1.0))
                } catch {
                    return
                }
            }

            if !url.isEmpty {
                await checkUrl(string: fullUrl)
            }
        }

        if url.isEmpty {
            loginState = .empty
        }

        if url.starts(with: "https://") {
            scheme = .https
            url.replace(/^https:\/\//, with: "")
        }

        if url.starts(with: "http://") {
            scheme = .http
            url.replace(/^http:\/\//, with: "")
        }
    }

    func decodeDetails(_ body: Data) -> String? {
        struct Response: Decodable {
            var detail: String
        }
        if let detail = try? JSONDecoder().decode(Response.self, from: body).detail {
            return detail
        }

        if let detail = String(data: body, encoding: .utf8) {
            return detail
        }

        return nil
    }

    func checkUrl(string value: String) async {
        Logger.shared.notice("Checking backend URL \(value)")
        guard !value.isEmpty else {
            Logger.shared.notice("Value is empty")
            loginState = .empty
            return
        }

        let apiUrl: URL

        do {
            (_, apiUrl) = try deriveUrl(string: value)
        } catch {
            Logger.shared.error("Cannot derive URL: \(value) -> \(error)")
            loginState = .error(.init(invalidUrl: error))
            return
        }

        var request = URLRequest(url: apiUrl)
        extraHeaders.apply(toRequest: &request)
        request.setValue("application/json; version=\(ApiRepository.minimumApiVersion)", forHTTPHeaderField: "Accept")

        Logger.api.info("Headers for check request: \(request.allHTTPHeaderFields ?? [:])")

        do {
            Logger.shared.info("Checking valid-looking URL \(apiUrl)")
            loginState = .checking
            let selectedIdentity = selectedIdentity
            Logger.shared.info("Using identity: \(selectedIdentity?.name ?? "none")")

            let session = URLSession(configuration: .default,
                                     delegate: PaperlessURLSessionDelegate(identity: selectedIdentity),
                                     delegateQueue: nil)

            let (data, response) = try await session.getData(for: request)

            let httpResponse = response as? HTTPURLResponse

            if let statusCode = httpResponse?.statusCode, statusCode != 200 {
                Logger.shared.warning("Checking API status was not 200 but \(statusCode)")
                switch statusCode {
                case 400:
                    loginState = .error(.badRequest)
                case 406:
                    loginState = .error(.insufficientApiVersion)
                default:
                    loginState = .error(.unexpectedStatusCode(statusCode: statusCode,
                                                              details: decodeDetails(data)))
                }
                return
            }

            _ = try JSONDecoder().decode([String: URL].self, from: data)
            loginState = .valid

        } catch is CancellationError {
            // do nothing
            return
        } catch let error as NSError where error.domain == NSURLErrorDomain && NSURLError(rawValue: error.code) == NSURLError.cancelled {
            // also a cancellation error
            return
        } catch let error as NSError where LoginViewModel.isLocalNetworkDenied(error) {
            Logger.shared.error("Unable to connect to API: local network access denied")
            loginState = .error(.localNetworkDenied)
        } catch let error as NSError where error.domain == NSURLErrorDomain && NSURLError.value(error.code, inCategory: .ssl) {
            Logger.shared.error("Certificate error when connecting to the API: \(error)")
            loginState = .error(.init(certificate: error))
        } catch {
            Logger.shared.error("Checking API error: \(error)")
            loginState = .error(.init(other: error))
            return
        }
    }

    nonisolated
    static func isLocalNetworkDenied(_ error: NSError) -> Bool {
        Logger.shared.debug("Checking API NSError: \(error)")
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }
        Logger.shared.debug("Checking API underlying NSError: \(underlying)")

        guard let reason = (underlying.userInfo["_NSURLErrorNWPathKey"] as? NSObject)?.value(forKey: "reason") as? Int else {
            return false
        }

        Logger.shared.debug("Unsatisfied reason code is: \(reason)")
        return reason == 29
    }

    var fullUrl: String {
        "\(scheme)://\(url)"
    }

    var isLocalAddress: Bool {
        Self.isLocalAddress(fullUrl)
    }

    nonisolated
    static func isLocalAddress(_ url: String) -> Bool {
        guard let components = URLComponents(string: url), let host = components.host else {
            return false
        }

        if host == "localhost" {
            return true
        }

        guard let match = try? /(\d+)\.(\d+)\.(\d+)\.(\d+)/.wholeMatch(in: host) else {
            return false
        }

        let ip = (UInt(match.1)!, UInt(match.2)!, UInt(match.3)!, UInt(match.4)!)

        if ip == (127, 0, 0, 1) {
            return true
        }

        return (ip >= (10, 0, 0, 0) && ip <= (10, 255, 255, 255)) || (ip >= (172, 16, 0, 0) && ip <= (172, 31, 255, 255)) || (ip >= (192, 168, 0, 0) && ip <= (192, 168, 255, 255))
    }

    private func fetchToken(url tokenUrl: URL) async throws -> String {
        let username = username
        let password = password
        Logger.shared.info("Fetching token from username \(username) and password \(password)")

        do {
            struct TokenRequest: Encodable {
                var username: String
                var password: String
            }

            let json = try JSONEncoder().encode(TokenRequest(username: username,
                                                             password: password))

            var request = URLRequest(url: tokenUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = json
            extraHeaders.apply(toRequest: &request)

            Logger.shared.info("Sending login request with headers: \(request.allHTTPHeaderFields ?? [:])")

            let session = URLSession(configuration: .default, delegate: PaperlessURLSessionDelegate(identity: selectedIdentity), delegateQueue: nil)
            let (data, response) = try await session.getData(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            if statusCode != 200 {
                Logger.shared.error("Token request response was not 200 but \(statusCode, privacy: .public), \(String(decoding: data, as: UTF8.self))")
                if statusCode == 400 {
                    throw LoginError.invalidLogin
                }
                throw LoginError.unexpectedStatusCode(statusCode: statusCode, details: decodeDetails(data))
            }

            struct TokenResponse: Decodable {
                var token: String
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            return tokenResponse.token
        }
    }

    func validateCredentials() async throws(LoginError) -> StoredConnection {
        let fullUrl = fullUrl
        Logger.shared.info("Validating credentials against url: \(fullUrl)")
        credentialState = .validating

        let baseUrl: URL
        let tokenUrl: URL
        do {
            (baseUrl, tokenUrl) = try deriveUrl(string: fullUrl, suffix: "token")
        } catch {
            // In principle this is checked before, so should not fail here
            Logger.shared.warning("Error making URL for logging in (url: \(fullUrl)) \(error)")
            throw LoginError(invalidUrl: error)
        }

        do {
            let connection: Connection

            let makeConnection = { [self] (token: String?) -> Connection in
                Connection(url: baseUrl,
                           token: token,
                           extraHeaders: extraHeaders,
                           identityName: selectedIdentity?.name)
            }

            switch credentialMode {
            case .usernameAndPassword:
                Logger.shared.info("Credential mode is username and password")

                let token = try await fetchToken(url: tokenUrl)
                Logger.shared.info("Username and password are valid, have token")
                connection = makeConnection(token)

            case .token:
                connection = makeConnection(token)

            case .none:
                connection = makeConnection(nil)
            }

            Logger.shared.debug("Building repository instance with connection for testing")
            let repository = await ApiRepository(connection: connection)

            Logger.shared.info("Requesting current user")
            let currentUser = try await repository.currentUser()

            Logger.shared.info("Have user: \(currentUser.username)")

            if currentUser.username != username {
                Logger.api.warning("Username from login and logged in username not the same")
            }

            let stored = StoredConnection(url: baseUrl,
                                          extraHeaders: extraHeaders,
                                          user: currentUser,
                                          identity: selectedIdentity?.name)
            if let token = connection.token {
                Logger.api.info("Have token for connection, storing")
                try stored.setToken(token)
            } else {
                Logger.api.info("No token for connection, leaving nil")
            }

            Logger.api.info("Credentials are valid")

            credentialState = .valid

            return stored

        } catch RequestError.forbidden {
            Logger.shared.error("User logging in does not have permissions to get permissions")
            credentialState = .error(.insufficientPermissions)
            throw .insufficientPermissions
        } catch RequestError.unauthorized {
            credentialState = .error(.invalidToken)
            throw .invalidLogin
        } catch let error as LoginError {
            Logger.shared.error("Error during login with url \(error)")
            credentialState = .error(error)
            throw error
        } catch {
            Logger.shared.error("Error during login with url \(error)")
            credentialState = .error(.init(other: error))
            throw LoginError(other: error)
        }
    }
}
