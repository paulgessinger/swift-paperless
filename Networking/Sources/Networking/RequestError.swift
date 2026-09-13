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

  // A connectivity-class transport failure: the request never produced a
  // response because the device is offline or the server couldn't be reached.
  //
  // `code` is kept rather than flattened into a message, because what it can
  // mean for the *write* that failed differs (see `ErrorSuppression`). `kind`
  // is the device-offline vs. server-unreachable verdict, decided when the
  // request failed (see `TransportFailureKind`) and frozen into the value, so
  // an error shown later isn't reclassified against a network that has since
  // come back.
  //
  // `detail` is the system's localized message, which is the same for every
  // request that fails the same way. That keeps two failures of one outage
  // `==`, whereas the underlying `URLError`s never are: their userInfo carries
  // the failing URL and a per-request task id.
  case connectivity(code: NSURLError, kind: TransportFailureKind, detail: String)

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
  /// Map a `URLSession` failure onto the request-error vocabulary, or `nil` if
  /// it isn't one we reinterpret.
  ///
  /// - SSL codes become ``certificate(detail:)``.
  /// - Connectivity-class codes become ``connectivity(code:kind:detail:)``,
  ///   classified against `path`. The default samples ``NetworkPathProbe``
  ///   right here, so call this where the request failed, not later.
  /// - `badURL`/`unsupportedURL` (the address itself is unusable) and
  ///   `httpTooManyRedirects`/`redirectToNonExistentLocation`/
  ///   `badServerResponse`/`resourceUnavailable` (something *did* answer, just
  ///   not usefully) stay ``other(_:)`` with the system message: neither says
  ///   anything about reachability, so the path status doesn't apply.
  /// - Everything else, including cancellation and the file-I/O codes a
  ///   download can hit, is `nil`.
  public init?(
    from error: NSError, path: @autoclosure () -> NetworkPathStatus = NetworkPathProbe.sample()
  ) {
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

    if let kind = TransportFailureKind(code: code, path: path()) {
      self = .connectivity(code: code, kind: kind, detail: string(for: error))
      return
    }

    switch code {
    case .badURL, .unsupportedURL, .httpTooManyRedirects, .resourceUnavailable,
      .redirectToNonExistentLocation, .badServerResponse:
      self = .other(string(for: error))
    default:
      return nil
    }
  }

  /// Whether this is a connectivity-class transport failure.
  public var isConnectivity: Bool {
    if case .connectivity = self { return true }
    return false
  }

  /// Normalize an error thrown by a `URLSession` transport call made by a
  /// repository: a connectivity-class failure becomes
  /// ``connectivity(code:kind:detail:)``, classified against the path status
  /// sampled *now*. Anything else — cancellation, SSL, the other URL codes, and
  /// errors from other domains — passes through untouched, as it did before.
  public static func normalizingTransportFailure(
    _ error: any Error, path: @autoclosure () -> NetworkPathStatus = NetworkPathProbe.sample()
  ) -> any Error {
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain,
      let code = NSURLError(rawValue: nsError.code),
      let kind = TransportFailureKind(code: code, path: path())
    else {
      return error
    }
    return RequestError.connectivity(code: code, kind: kind, detail: string(for: error))
  }
}

// `localizedDescription` for a connectivity failure is the system message it
// replaced ("Could not connect to the server."). Code that only knows
// `localizedDescription` — the Offline & Sync failure list, the "not saved"
// toast's details — therefore reads the same as it did when the raw `URLError`
// reached it. Every other case keeps the default bridging.
extension RequestError: CustomNSError {
  public var errorUserInfo: [String: Any] {
    if case .connectivity(_, _, let detail) = self {
      return [NSLocalizedDescriptionKey: detail]
    }
    return [:]
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
