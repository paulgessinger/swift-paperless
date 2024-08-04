//
//  LoginViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 31.07.2024.
//

import Foundation
import os

enum LoginState {
    case empty
    case checking
    case valid
    case error(_: LoginError)
}

@MainActor
@Observable
class LoginViewModel {
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

    var username: String = ""
    var password: String = ""

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

        let apiUrl: URL

        do {
            (_, apiUrl) = try LoginViewModel.deriveUrl(string: value)
        } catch {
            Logger.shared.error("Cannot derive URL: \(value) -> \(error)")
            loginState = .error(.invalidUrl(error as? LocalizedError))
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
        } catch let error as NSError where error.code == -1202 {
            Logger.shared.error("Certificate error when connecting to the API: \(error)")
            loginState = .error(.certificate(error))
        } catch {
            Logger.shared.error("Checking API error: \(error)")
            loginState = .error(.other(error))
            return
        }
    }

    nonisolated
    static func deriveUrl(string value: String, suffix: String = "") throws -> (base: URL, resolved: URL) {
        let url: URL?

        let pattern = /(\w+):\/\/(.*)/

        if let matches = try? pattern.wholeMatch(in: value) {
            let scheme = matches.1
            let rest = matches.2
            if scheme != "http", scheme != "https" {
                Logger.shared.error("Encountered invalid scheme \(scheme)")
                throw UrlError.invalidScheme(String(scheme))
            }
            url = URL(string: "\(scheme)://\(rest)")
        } else {
            url = URL(string: "https://\(value)")
        }

        guard let url, var url = URL(string: url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            Logger.shared.notice("Derived URL \(value) was invalid")
            throw UrlError.other
        }

        let base = url

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.shared.notice("Could not parse URL \(url) into components")
            throw UrlError.cannotSplit
        }

        guard let host = components.host, !host.isEmpty else {
            Logger.shared.error("URL \(url) had empty host")
            throw UrlError.emptyHost
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
