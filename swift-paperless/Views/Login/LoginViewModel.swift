//
//  LoginViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 31.07.2024.
//

import Foundation
import os

enum LoginError: DisplayableError {
    case urlInvalid
    case invalidLogin

    case invalidResponse(statusCode: Int, details: String?)
    case localNetworkDenied

    case insufficientPermissions

    case other(_: Error)

    var message: String {
        String(localized: .login(.errorMessage))
    }

    var details: String? {
        String(localized: _details)
    }

    private var _details: LocalizedStringResource {
        switch self {
        case .urlInvalid:
            return .login(.errorUrlInvalid)

        case .invalidLogin:
            return .login(.errorLoginInvalid)

        case let .invalidResponse(statusCode, details):
            if let details {
                return .login(.errorInvalidResponseDetails(statusCode, details))
            } else {
                return .login(.errorInvalidResponse(statusCode))
            }

        case .localNetworkDenied:
            return .login(.errorLocalNetworkDenied)

        case .insufficientPermissions:
            return .login(.insufficientPermissions)

        case let .other(error):
            return .login(.errorOther(error.localizedDescription))
        }
    }

    var documentationLink: URL? {
        switch self {
        case .localNetworkDenied:
            DocumentationLinks.localNetworkDenied
        case .insufficientPermissions:
            DocumentationLinks.insufficientPermissions
        default:
            nil
        }
    }
}

@MainActor
@Observable
class LoginViewModel {
    enum LoginState {
        case empty
        case checking
        case valid
        case error(_: LoginError)
    }

    var loginState = LoginState.empty

    var loginStateValid: Bool {
        switch loginState {
        case .valid, .error: // Error is technically not valid, but we want to allow retrying
            return true
        default:
            return false
        }
    }

    var extraHeaders: [ConnectionManager.HeaderValue] = []

    var selectedIdentity: String?

    func decodeDetails(_ body: Data) -> String? {
        struct Response: Decodable {
            var details: String
        }
        return try? JSONDecoder().decode(Response.self, from: body).details
    }

    func checkUrl(string value: String) async {
        Logger.shared.notice("Checking backend URL \(value)")
        guard !value.isEmpty else {
            Logger.shared.notice("Value is empty")
            loginState = .empty
            return
        }

        guard let (_, apiUrl) = LoginViewModel.deriveUrl(string: value) else {
            Logger.shared.notice("Cannot to URL: \(value)")
            loginState = .error(.urlInvalid)
            return
        }

        var request = URLRequest(url: apiUrl)
        extraHeaders.apply(toRequest: &request)

        Logger.api.info("Headers for check request: \(request.allHTTPHeaderFields ?? [:])")

        do {
            Logger.shared.info("Checking valid-looking URL \(apiUrl)")
            loginState = .checking

            let session = URLSession(configuration: .default, delegate: PaperlessURLSessionDelegate(identityName: selectedIdentity), delegateQueue: nil)

            let (data, response) = try await session.getData(for: request)

            if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 200 {
                Logger.shared.warning("Checking API status was not 200 but \(statusCode)")
                loginState = .error(.invalidResponse(statusCode: statusCode,
                                                     details: decodeDetails(data)))
                return
            }

            struct Response: Decodable {
                var correspondents: URL
                var document_types: URL
                var logs: URL
                var mail_accounts: URL
                var mail_rules: URL
                var saved_views: URL
                var storage_paths: URL
                var tags: URL
                var tasks: URL
            }

            _ = try JSONDecoder().decode(Response.self, from: data)
            loginState = .valid

        } catch let error as NSError where LoginViewModel.isLocalNetworkDenied(error) {
            Logger.shared.error("Unable to connect to API: local network access denied")
            loginState = .error(.localNetworkDenied)
        } catch {
            Logger.shared.error("Checking API error: \(error)")
            loginState = .error(.other(error))
            return
        }
    }

    nonisolated
    static func deriveUrl(string value: String, suffix: String = "") -> (base: URL, resolved: URL)? {
        let url: URL?

        let pattern = /(\w+):\/\/(.*)/

        if let matches = try? pattern.wholeMatch(in: value) {
            let scheme = matches.1
            let rest = matches.2
            if scheme != "http", scheme != "https" {
                Logger.shared.error("Encountered invalid scheme \(scheme)")
                return nil
            }
            url = URL(string: "\(scheme)://\(rest)")
        } else {
            url = URL(string: "https://\(value)")
        }

        guard let url, var url = URL(string: url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            Logger.shared.notice("Derived URL \(value) was invalid")
            return nil
        }

        let base = url

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.shared.notice("Could not parse URL \(url) into components")
            return nil
        }

        guard let host = components.host, !host.isEmpty else {
            Logger.shared.error("URL \(url) had empty host")
            return nil
        }

        assert(components.scheme != nil)

        url = url.appending(component: "api", directoryHint: .isDirectory)
        if !suffix.isEmpty {
            url = url.appending(component: suffix, directoryHint: .isDirectory)
        }

        Logger.shared.notice("Derive URL: \(value) + \(suffix) -> \(url)")

        return (base, url)
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

    nonisolated
    static func isLocalAddress(_ url: String) -> Bool {
        guard let components = URLComponents(string: url), let host = components.host else {
            return false
        }

        guard let match = try? /(\d+)\.(\d+)\.(\d+)\.(\d+)/.wholeMatch(in: host) else {
            return false
        }

        let ip = (UInt(match.1)!, UInt(match.2)!, UInt(match.3)!, UInt(match.4)!)

        return (ip >= (10, 0, 0, 0) && ip <= (10, 255, 255, 255)) || (ip >= (172, 16, 0, 0) && ip <= (172, 31, 255, 255)) || (ip >= (192, 168, 0, 0) && ip <= (192, 168, 255, 255))
    }
}
