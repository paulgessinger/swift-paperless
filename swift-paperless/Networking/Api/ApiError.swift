//
//  ApiError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.05.2024.
//

import Foundation

enum RequestError: Error {
    // Error building a request in the first place
    case invalidRequest

    // Anything other than HTTPResponse was returned
    case invalidResponse

    // A status code that was not expected was returned
    case unexpectedStatusCode(code: Int, detail: String?)

    // A 403 status code was returned (and was not expected)
    case forbidden(detail: String)

    // A 402 status code was returned (and was not expected)
    case unauthorized(detail: String)

    // A 406 status code was returned. Use by paperless-ngx to indicate that the requested API version is not accepted
    case unsupportedVersion
}

extension RequestError: DisplayableError {
    var message: String {
        String(localized: .localizable(.errorDefaultMessage))
    }

    var details: String? {
        let res: LocalizedStringResource = switch self {
        case .invalidRequest:
            .localizable(.requestErrorInvalidRequest)
        case .invalidResponse:
            .localizable(.requestErrorInvalidResponse)
        case let .unexpectedStatusCode(code, _):
            .localizable(.requestErrorUnexpectedStatusCode(code))
        case let .forbidden(detail):
            .localizable(.requestErrorForbidden(detail))
        case let .unauthorized(detail):
            .localizable(.requestErrorUnauthorized(detail))
        case .unsupportedVersion:
            .localizable(.requestErrorUnsupportedVersion(ApiRepository.minimumApiVersion))
        }

        return String(localized: res)
    }

    var documentationLink: URL? {
        switch self {
        case .forbidden:
            DocumentationLinks.insufficientPermissions
        case .unsupportedVersion:
            DocumentationLinks.supportedVersions
        default:
            nil
        }
    }
}

struct ResourceForbidden<Resource: Model>: DisplayableError {
    init(_: Resource.Type, response: String) {
        self.response = response
    }

    let response: String

    var message: String {
        String(localized: .localizable(.apiForbiddenErrorMessage(Resource.localizedName)))
    }

    var details: String? {
        String(localized: .localizable(.apiForbiddenDetails(Resource.localizedName, response)))
    }

    var documentationLink: URL? { DocumentationLinks.forbidden }
}
