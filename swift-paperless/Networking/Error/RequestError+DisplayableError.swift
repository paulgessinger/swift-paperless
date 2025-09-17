//
//  RequestError+DisplayableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.03.25.
//
import Common
import Foundation
import Networking

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

    case .unexpectedStatusCode(let code, let details):
      var msg = String(localized: .localizable(.requestErrorUnexpectedStatusCode(code.description)))

      if let details {
        if !Self.isMTLSError(code: code, message: details) {
          // We're not sure this is an SSL error, show details just in case
          msg +=
            " " + label + " "
            + details
        } else {
          msg += " " + .localizable(.requestErrorMTLS)
        }
      }
      raw = msg

    case .forbidden(let detail):
      var s = String(localized: .localizable(.requestErrorForbidden))
      if let detail {
        s +=
          " " + label + " "
          + detail
      }
      raw = s

    case .unauthorized(let detail):
      var s = String(localized: .localizable(.requestErrorUnauthorized))
      s += " " + label + " " + detail
      raw = s

    case .unsupportedVersion:
      raw = String(
        localized: .localizable(.requestErrorUnsupportedVersion(ApiRepository.minimumApiVersion)))

    case .localNetworkDenied:
      raw = String(localized: .localizable(.requestErrorLocalNetworkDenied))

    case .certificate(let detail):
      raw = String(localized: .localizable(.requestErrorCertificate)) + " " + detail

    case .other(let detail):
      raw = detail
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
    case .unexpectedStatusCode(let code, let detail)
    where code == .badRequest && detail != nil && Self.isMTLSError(code: code, message: detail!):
      DocumentationLinks.certificate
    case .certificate:
      DocumentationLinks.certificate
    default:
      nil
    }
  }

  static func isMTLSError(code: HTTPStatusCode, message: String) -> Bool {
    guard code == .badRequest else {
      return false
    }

    return message.contains("SSL") || message.contains("certificate")
  }
}
