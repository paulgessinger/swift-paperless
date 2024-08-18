//
//  LoginViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 31.07.2024.
//

import Foundation
import os

enum LoginState: Equatable {
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

    var selectedIdentity: TLSIdentity?

    var username: String = ""
    var password: String = ""

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

    func onChangeUrl(immediate: Bool = false) {
        checkUrlTask?.cancel()
        checkUrlTask = Task {
            if !immediate {
                do {
                    try await Task.sleep(for: .seconds(0.8))
                } catch {}
                guard !Task.isCancelled else {
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
            (_, apiUrl) = try deriveUrl(string: value)
        } catch is CancellationError {
            // do nothing
            return
        } catch {
            Logger.shared.error("Cannot derive URL: \(value) -> \(error)")
            loginState = .error(.init(invalidUrl: error))
            return
        }

        var request = URLRequest(url: apiUrl)
        extraHeaders.apply(toRequest: &request)

        Logger.api.info("Headers for check request: \(request.allHTTPHeaderFields ?? [:])")

        do {
            Logger.shared.info("Checking valid-looking URL \(apiUrl)")
            loginState = .checking

            let session = URLSession(configuration: .default,
                                     delegate: PaperlessURLSessionDelegate(identity: selectedIdentity),
                                     delegateQueue: nil)

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
            loginState = .error(.init(certificate: error))
        } catch is CancellationError {
            // do nothing
            return
        } catch let error as NSError where error.code == -999 {
            // also a cancellation error
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
}
