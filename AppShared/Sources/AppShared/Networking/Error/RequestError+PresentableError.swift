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
  public var presentation: some View {
    switch self {
    case .unsupportedVersion(let sentVersion):
      Text(
        .app(
          .requestErrorUnsupportedVersion(
            ApiRepository.minimumApiVersion, ApiRepository.maximumApiVersion))
      )
      .bold()
      if let sentVersion {
        Text(.app(.requestErrorDetailLabel)) + Text(": sent version=\(sentVersion)")
      }

    case .unexpectedStatusCode(let code, let details):
      Text(.app(.requestErrorUnexpectedStatusCode(code.description)))
        .bold()

      if let details {
        if !Self.isMTLSError(code: code, message: details) {
          // We're not sure this is an SSL error, show details just in case
          Text(.app(.requestErrorDetailLabel)) + Text(": ")
            + (Text(details).italic())
        }
        Text(.app(.requestErrorMTLS))
      }

    case .invalidRequest:
      Text(.app(.requestErrorInvalidRequest))
        .bold()

    case .invalidResponse:
      Text(.app(.requestErrorInvalidResponse))
        .bold()

    case .forbidden(let detail):
      Text(.app(.requestErrorForbidden))
        .bold()
      if let detail {
        Text(.app(.requestErrorDetailLabel)) + Text(": ")
          + (Text(detail).italic())
      }

    case .unauthorized(let detail):
      Text(.app(.requestErrorUnauthorized))

      Text(.app(.requestErrorDetailLabel)) + Text(": ")
        + (Text(detail).italic())

    case .localNetworkDenied:
      Text(app: .requestErrorLocalNetworkDenied)

    case .certificate(let detail):
      Text(.app(.requestErrorCertificate))
        .bold()
      Text(.app(.requestErrorDetailLabel)) + Text(": ")
        + (Text(detail).italic())

    case .other(let detail):
      Text(detail)
        .bold()
    }
  }
}
