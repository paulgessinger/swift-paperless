//
//  RequestError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.05.2024.
//

import Common
import DataModel
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

struct ResourceForbidden<Resource>: Error {
    let response: String?

    init(_: Resource.Type, response: String?) {
        self.response = response
    }
}
