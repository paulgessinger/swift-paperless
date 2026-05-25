//
//  OIDCError+LocalizedError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.05.26.
//

import Foundation
import Networking

// OIDCError is declared in the Networking package without any localized strings
// (matching the RequestError pattern). The user-facing, localized descriptions
// live here in the app layer, backed by the Login string catalog.
extension OIDCError: @retroactive LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .missingCSRF:
      String(localized: .login(.oidcErrorMissingCsrf))
    case .missingScope:
      String(localized: .login(.oidcErrorMissingScope))
    case .missingCode:
      String(localized: .login(.oidcErrorMissingCode))
    case .missingConfigurationURL:
      String(localized: .login(.oidcErrorMissingConfigurationUrl))
    case .invalidState:
      String(localized: .login(.oidcErrorInvalidState))
    case .authFailed:
      String(localized: .login(.oidcErrorAuthFailed))
    case .invalidURL:
      String(localized: .login(.oidcErrorInvalidUrl))
    case .invalidRedirectURL:
      String(localized: .login(.oidcErrorInvalidRedirectUrl))
    case .formBodyEncodingFailed:
      String(localized: .login(.oidcErrorFormBodyEncodingFailed))
    case .tokenExchangeFailed(let error, let description):
      if let description {
        String(localized: .login(.oidcErrorTokenExchangeFailed("\(error) — \(description)")))
      } else {
        String(localized: .login(.oidcErrorTokenExchangeFailed(error)))
      }
    case .paperlessTokenExchangeFailed(let statusCode, let body):
      {
        let base = String(localized: .login(.oidcErrorPaperlessRejected("\(statusCode)")))
        return body.isEmpty ? base : "\(base) \(body)"
      }()
    }
  }
}
