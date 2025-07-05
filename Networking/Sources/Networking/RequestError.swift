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

  static func unexpectedStatusCode(code: HTTPStatusCode, body: Data) -> Self {
    // Try to extract error messages from JSON response
    if let extractedError = extractErrorMessage(from: body) {
      return .unexpectedStatusCode(code: code, detail: extractedError)
    }

    let bodyString = String(data: body, encoding: .utf8) ?? "[NO BODY]"
    return .unexpectedStatusCode(code: code, detail: bodyString)
  }

  static func forbidden(body: Data) -> Self {
    // Try to extract error messages from JSON response
    if let extractedError = extractErrorMessage(from: body) {
      return .forbidden(detail: extractedError)
    }

    let bodyString = String(data: body, encoding: .utf8) ?? "[NO BODY]"
    return .forbidden(detail: bodyString)
  }

  static func unauthorized(body: Data) -> Self {
    // Try to extract error messages from JSON response
    if let extractedError = extractErrorMessage(from: body) {
      return .unauthorized(detail: extractedError)
    }

    let bodyString = String(data: body, encoding: .utf8) ?? "[NO BODY]"
    return .unauthorized(detail: bodyString)
  }

  private static func extractErrorMessage(from data: Data) -> String? {
    do {
      let decoder = JSONDecoder()

      // First try to decode as a simple detail response
      if let detailResponse = try? decoder.decode([String: String].self, from: data),
        let detail = detailResponse["detail"]
      {
        return detail
      }

      // Then try to decode as array response with non_field_errors
      let response = try decoder.decode([String: [ErrorField]].self, from: data)

      // Look for non_field_errors in any array within the JSON
      for (_, fields) in response {
        for field in fields {
          if let nonFieldErrors = field.non_field_errors, !nonFieldErrors.isEmpty {
            if nonFieldErrors.count == 1 {
              return nonFieldErrors[0]
            } else {
              return nonFieldErrors.enumerated()
                .map { "\($0 + 1). \($1)" }
                .joined(separator: "\n")
            }
          }
        }
      }
    } catch {
      // If decoding fails, return nil to fall back to using the body as-is
      return nil
    }

    return nil
  }

  private struct ErrorField: Codable {
    let non_field_errors: [String]?
  }
}

private func string(for error: any Error) -> String {
  (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
}

extension RequestError {
  public init?(from error: NSError) {
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
    case .badURL, .unsupportedURL, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
      .dnsLookupFailed, .httpTooManyRedirects, .resourceUnavailable, .notConnectedToInternet,
      .redirectToNonExistentLocation, .badServerResponse:
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
