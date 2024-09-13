//
//  ApiError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.05.2024.
//

import Foundation

enum RequestError: Error {
    case invalidRequest
    case invalidResponse
    case unexpectedStatusCode(code: Int)
    case forbidden(detail: String)
    case unauthorized(detail: String)
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
