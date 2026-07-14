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
  public var message: String {
    String(localized: .app(.errorDefaultMessage))
  }

  public var details: String? {
    let label = String(localized: .app(.requestErrorDetailLabel)) + ":"
    let raw: String

    switch self {
    case .invalidRequest:
      raw = String(localized: .app(.requestErrorInvalidRequest))

    case .invalidResponse:
      raw = String(localized: .app(.requestErrorInvalidResponse))

    case .unexpectedStatusCode(let code, let details):
      var msg = String(localized: .app(.requestErrorUnexpectedStatusCode(code.description)))

      if let details {
        if !Self.isMTLSError(code: code, message: details) {
          // We're not sure this is an SSL error, show details just in case
          msg +=
            " " + label + " "
            + details
        } else {
          msg += " " + .app(.requestErrorMTLS)
        }
      }
      raw = msg

    case .forbidden(let detail):
      var s = String(localized: .app(.requestErrorForbidden))
      if let detail {
        s +=
          " " + label + " "
          + detail
      }
      raw = s

    case .unauthorized(let detail):
      var s = String(localized: .app(.requestErrorUnauthorized))
      s += " " + label + " " + detail
      raw = s

    case .unsupportedVersion(let sentVersion):
      var s = String(
        localized: .app(
          .requestErrorUnsupportedVersion(
            ApiRepository.minimumApiVersion, ApiRepository.maximumApiVersion)))
      if let sentVersion {
        s += " (\(label) sent version=\(sentVersion))"
      }
      raw = s

    case .localNetworkDenied:
      raw = String(localized: .app(.requestErrorLocalNetworkDenied))

    case .certificate(let detail):
      raw = String(localized: .app(.requestErrorCertificate)) + " " + detail

    case .connectivity(let code, let detail):
      // The system's message ("Could not connect to the server.") says what
      // happened but not what to do about it, and the causes are wildly
      // different — a stopped server, a typo in the URL, a VPN that dropped.
      // Spell them out.
      raw = detail + "\n\n" + Self.connectivityHint(for: code)

    case .other(let detail):
      raw = detail
    }

    // Single source strings that might contain markdown markup: use AttributedString to remove them.
    // `inlineOnlyPreservingWhitespace` because the default block parse discards
    // line breaks, which would run a multi-paragraph detail together into one
    // sentence ("...the server.The server could not be reached...").
    if let str = try? AttributedString(
      markdown: raw,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    {
      return String(str.characters)
    }
    return raw
  }

  public var documentationLink: URL? {
    switch self {
    case .forbidden:
      DocumentationLinks.insufficientPermissions
    case .unsupportedVersion(_):
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

  /// What a transport failure is likely to mean, in terms the user can act on.
  ///
  /// The `NSURLError` code is the only thing that distinguishes these cases —
  /// which is why the repository carries it through rather than flattening the
  /// failure into a message.
  public static func connectivityHint(for code: NSURLError) -> String {
    switch code {
    case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
      String(localized: .app(.requestErrorConnectivityHintOffline))

    case .cannotFindHost, .dnsLookupFailed, .badURL, .unsupportedURL,
      .redirectToNonExistentLocation:
      String(localized: .app(.requestErrorConnectivityHintHostNotFound))

    // Connection refused, timed out, dropped mid-flight, ...: we reached the
    // network but not a working server at the other end.
    default:
      String(localized: .app(.requestErrorConnectivityHintUnreachable))
    }
  }

  public static func isMTLSError(code: HTTPStatusCode, message: String) -> Bool {
    guard code == .badRequest else {
      return false
    }

    return message.contains("SSL") || message.contains("certificate")
  }
}
