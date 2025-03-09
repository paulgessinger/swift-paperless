//
//  LoginError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.08.2024.
//

import Foundation
import Networking

private func string(for error: any Error) -> String {
    (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
}

enum LoginError: DisplayableError, Equatable {
    case invalidUrl(_: UrlError)

    case invalidLogin(detail: String? = nil)

    case otpRequired

    case invalidToken

    case other(_: String)

    case request(_: RequestError)

    init(other error: any Error) { self = .other(string(for: error)) }

    init(certificate error: any Error) { self = .request(.certificate(detail: string(for: error))) }
}

extension LoginError {
    var message: String {
        String(localized: .login(.errorMessage))
    }

    var details: String? {
        switch self {
        case let .invalidUrl(error):
            var msg = String(localized: .login(.errorUrlInvalid))
            if let desc = error.errorDescription {
                msg += ": \(desc)"
            }
            return msg
        case .invalidLogin:
            return String(localized: .login(.errorLoginInvalid))
        case .invalidToken:
            return String(localized: .login(.errorMessage))
        case let .other(error):
            return error
        case let .request(error):
            return error.details
        case .otpRequired:
            return String(localized: .login(.otpDescription))
        }
    }

    var documentationLink: URL? {
        switch self {
        case let .request(error):
            error.documentationLink
        default:
            nil
        }
    }
}
