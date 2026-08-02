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

  // A 406 status code was returned. Use by paperless-ngx to indicate that the requested API version is not accepted.
  // `sentVersion` is the API version we put in the failing request's Accept header, when known — useful for
  // diagnosing the case where the backend rejects a version it previously advertised as supported.
  case unsupportedVersion(sentVersion: UInt?)

  case localNetworkDenied

  case certificate(detail: String)

  // A transport-level failure: the request never produced a response (host
  // unreachable, DNS failure, timeout, device offline, ...).
  //
  // `code` is carried through rather than being flattened into a message so
  // policy code downstream can still tell these apart — `ErrorSuppression`
  // needs to distinguish "the device is offline" (a banner already says so)
  // from "this server is unreachable" (nothing else reports it).
  //
  // `detail` is the localized system message, which is identical for every
  // request that fails the same way. That makes two failures against the same
  // host `==`, whereas the underlying `URLError`s are not: their bridged
  // `NSError.userInfo` carries the failing URL and a per-request task id, so
  // no two are ever equal. Collapsing a fan-out of requests into one error
  // (and so one toast) depends on this.
  case connectivity(code: NSURLError, detail: String)

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
  /// Map a `URLSession` transport failure onto the request-error vocabulary.
  ///
  /// Returns `nil` for anything that isn't a transport failure we want to
  /// reinterpret: errors from another domain, cancellation (callers handle that
  /// separately, and it must never be shown), and the file-I/O codes a download
  /// can hit — those are about the local filesystem, not reachability.
  public init?(from error: NSError) {
    guard error.domain == NSURLErrorDomain else {
      return nil
    }

    guard let code = NSURLError(rawValue: error.code) else {
      return nil
    }

    guard code != .cancelled else {
      return nil
    }

    switch code.category {
    case .ssl:
      self = .certificate(detail: string(for: error))
    case .fileio:
      return nil
    case .other:
      self = .connectivity(code: code, detail: string(for: error))
    }
  }

  /// Normalize an error thrown by a `URLSession` transport call.
  ///
  /// Applied at the repository's transport boundary so that everything leaving
  /// a repository speaks `RequestError`, rather than the raw `URLError` that
  /// `URLSession` throws. Anything that isn't a recognized transport failure —
  /// including cancellation — is passed through untouched.
  public static func normalizing(_ error: any Error) -> any Error {
    RequestError(from: error as NSError) ?? error
  }
}

/// Non-generic view of ``ResourceForbidden`` so callers can recognise "this one
/// resource was forbidden" without knowing the resource type. `ResourceForbidden`
/// is generic, so `error is ResourceForbidden` is not expressible; this is.
public protocol ResourceForbiddenError: Error {
  var response: String? { get }
}

public struct ResourceForbidden<Resource>: ResourceForbiddenError {
  public let response: String?

  public init(_: Resource.Type, response: String?) {
    self.response = response
  }
}
