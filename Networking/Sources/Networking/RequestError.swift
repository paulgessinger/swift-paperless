//
//  RequestError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.05.2024.
//

import Common
import DataModel
import Foundation

public enum RequestError: Error, Equatable {
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

    // Can split this up into additional cases for customized error messages
    case other(_: String)
}

private func string(for error: any Error) -> String {
    (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
}

public extension RequestError {
    init?(from error: NSError) {
        guard error.domain == NSURLErrorDomain else {
            return nil
        }

        guard let code = NSURLError(rawValue: error.code) else {
            return nil
        }

        if code.category == .ssl {
            self = .certificate(detail: string(for: error))
            return
        }

        switch code {
        case .badURL, .unsupportedURL, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .httpTooManyRedirects, .resourceUnavailable, .notConnectedToInternet, .redirectToNonExistentLocation, .badServerResponse:
            self = .other(string(for: error))
        default:
            return nil
        }
    }
}

public struct ResourceForbidden<Resource>: Error {
    public let response: String?

    public init(_: Resource.Type, response: String?) {
        self.response = response
    }
}
