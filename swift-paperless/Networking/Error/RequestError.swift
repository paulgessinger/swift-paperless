//
//  RequestError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.05.2024.
//

import Common
import Foundation

enum RequestError: Error, Equatable {
    // Error building a request in the first place
    case invalidRequest

    // Anything other than HTTPResponse was returned
    case invalidResponse

    // A status code that was not expected was returned
    case unexpectedStatusCode(code: HTTPStatusCode, detail: String?)

    // A 403 status code was returned (and was not expected)
    case forbidden(detail: String?)

    // A 401 status code was returned (and was not expected)
    case unauthorized(detail: String)

    // A 406 status code was returned. Use by paperless-ngx to indicate that the requested API version is not accepted
    case unsupportedVersion

    case localNetworkDenied

    case certificate(detail: String)
}

extension RequestError: DisplayableError {
    var message: String {
        String(localized: .localizable(.errorDefaultMessage))
    }

    var details: String? {
        let label = String(localized: .localizable(.requestErrorDetailLabel)) + ":"
        let raw: String

        switch self {
        case .invalidRequest:
            raw = String(localized: .localizable(.requestErrorInvalidRequest))

        case .invalidResponse:
            raw = String(localized: .localizable(.requestErrorInvalidResponse))

        case let .unexpectedStatusCode(code, _):
            raw = String(localized: .localizable(.requestErrorUnexpectedStatusCode(code.description)))

        case let .forbidden(detail):
            var s = String(localized: .localizable(.requestErrorForbidden))
            if let detail {
                s += "\n\n" + label
                    + detail
            }
            raw = s

        case let .unauthorized(detail):
            var s = String(localized: .localizable(.requestErrorUnauthorized))
            s += "\n\n" + label + detail
            raw = s

        case .unsupportedVersion:
            raw = String(localized: .localizable(.requestErrorUnsupportedVersion(ApiRepository.minimumApiVersion)))

        case .localNetworkDenied:
            raw = String(localized: .localizable(.requestErrorLocalNetworkDenied))

        case let .certificate(detail):
            raw = String(localized: .localizable(.requestErrorCertificate)) + "\n\n" + detail
        }

        // Single source strings that might contain markdown markup: use AttributedString to remove them
        if let str = try? AttributedString(markdown: raw) {
            return String(str.characters)
        }
        return raw
    }

    var documentationLink: URL? {
        switch self {
        case .forbidden:
            DocumentationLinks.insufficientPermissions
        case .unsupportedVersion:
            DocumentationLinks.supportedVersions
        case .localNetworkDenied:
            DocumentationLinks.localNetworkDenied
        case .certificate:
            DocumentationLinks.certificate
        default:
            nil
        }
    }
}

struct ResourceForbidden<Resource: Model>: DisplayableError {
    init(_: Resource.Type, response: String?) {
        self.response = response
    }

    let response: String?

    var message: String {
        String(localized: .localizable(.apiForbiddenErrorMessage(Resource.localizedName)))
    }

    var details: String? {
        var msg = String(localized: .localizable(.apiForbiddenDetails(Resource.localizedName)))
        if let response {
            msg += "\n\n\(response)"
        }
        return msg
    }

    var documentationLink: URL? { DocumentationLinks.forbidden }
}
