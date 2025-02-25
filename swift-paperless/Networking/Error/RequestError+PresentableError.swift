//
//  RequestError+PresentableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.05.2024.
//

import Foundation
import Networking
import SwiftUI

extension RequestError: PresentableError {
    @ViewBuilder
    var presentation: some View {
        switch self {
        case .unsupportedVersion:
            Text(.localizable(.requestErrorUnsupportedVersion(ApiRepository.minimumApiVersion)))
                .bold()

        case let .unexpectedStatusCode(code, details):
            Text(.localizable(.requestErrorUnexpectedStatusCode(code.description)))
                .bold()

            if let details {
                if !Self.isMTLSError(code: code, message: details) {
                    // We're not sure this is an SSL error, show details just in case
                    Text(.localizable(.requestErrorDetailLabel)) + Text(": ")
                        + (Text(details).italic())
                }
                Text(.localizable(.requestErrorMTLS))
            }

        case .invalidRequest:
            Text(.localizable(.requestErrorInvalidRequest))
                .bold()

        case .invalidResponse:
            Text(.localizable(.requestErrorInvalidResponse))
                .bold()

        case let .forbidden(detail):
            Text(.localizable(.requestErrorForbidden))
                .bold()
            if let detail {
                Text(.localizable(.requestErrorDetailLabel)) + Text(": ")
                    + (Text(detail).italic())
            }

        case let .unauthorized(detail):
            Text(.localizable(.requestErrorUnauthorized))

            Text(.localizable(.requestErrorDetailLabel)) + Text(": ")
                + (Text(detail).italic())

        case .localNetworkDenied:
            Text(localizable: .requestErrorLocalNetworkDenied)

        case let .certificate(detail):
            Text(.localizable(.requestErrorCertificate))
                .bold()
            Text(.localizable(.requestErrorDetailLabel)) + Text(": ")
                + (Text(detail).italic())
            
        case let .other(detail):
            Text(detail)
                .bold()
        }
    }
}
