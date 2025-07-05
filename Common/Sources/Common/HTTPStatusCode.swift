//
//  HTTPStatusCode.swift
//  Common
//
//  Created by Paul Gessinger on 15.12.2024.
//

import Foundation

public enum HTTPStatusCode: Int, RawRepresentable, Sendable {
  // 1xx Informational Responses
  /// Client should continue the request or ignore if already finished.
  case `continue` = 100
  /// Server switching to a different protocol as requested.
  case switchingProtocols = 101
  /// Request received but no status is available yet (deprecated, WebDAV).
  case processing = 102
  /// Provides early hints for preloading resources (RFC 8297).
  case earlyHints = 103

  // 2xx Success
  /// Standard response for successful requests.
  case ok = 200
  /// Resource created successfully.
  case created = 201
  /// Request accepted but not yet processed.
  case accepted = 202
  /// Response from a transforming proxy.
  case nonAuthoritativeInformation = 203
  /// Request processed successfully, no content returned.
  case noContent = 204
  /// Request processed, reset document view.
  case resetContent = 205
  /// Partial content returned due to range headers.
  case partialContent = 206
  /// Response for multiple sub-requests (WebDAV).
  case multiStatus = 207
  /// Members already reported in a multistatus response (WebDAV).
  case alreadyReported = 208
  /// Instance-manipulations applied successfully (RFC 3229).
  case imUsed = 226

  // 3xx Redirection
  /// Multiple options for the requested resource.
  case multipleChoices = 300
  /// Resource moved permanently to a new URI.
  case movedPermanently = 301
  /// Resource found at a different URI (previously "Moved Temporarily").
  case found = 302
  /// Resource can be found at another URI using the GET method.
  case seeOther = 303
  /// Resource not modified since last retrieval.
  case notModified = 304
  /// Resource must be accessed via a proxy.
  case useProxy = 305
  /// Temporary redirect to another URI, method not changed.
  case temporaryRedirect = 307
  /// Permanent redirect to another URI, method not changed.
  case permanentRedirect = 308

  // 4xx Client Errors
  /// Malformed or invalid request.
  case badRequest = 400
  /// Authentication required and failed.
  case unauthorized = 401
  /// Payment required (reserved for future use).
  case paymentRequired = 402
  /// Server understood request but refuses to authorize it.
  case forbidden = 403
  /// Resource not found, may be available in the future.
  case notFound = 404
  /// HTTP method not allowed for the resource.
  case methodNotAllowed = 405
  /// Resource cannot generate acceptable content.
  case notAcceptable = 406
  /// Authentication required via proxy.
  case proxyAuthenticationRequired = 407
  /// Client request timed out.
  case requestTimeout = 408
  /// Conflict in the current resource state.
  case conflict = 409
  /// Resource no longer available and will not return.
  case gone = 410
  /// Content length required in the request.
  case lengthRequired = 411
  /// Preconditions in request headers not met.
  case preconditionFailed = 412
  /// Request payload too large to process.
  case contentTooLarge = 413
  /// URI provided is too long to process.
  case uriTooLong = 414
  /// Unsupported media type in the request.
  case unsupportedMediaType = 415
  /// Requested range is not satisfiable.
  case rangeNotSatisfiable = 416
  /// Server cannot meet the Expect header requirements.
  case expectationFailed = 417
  /// The server is a teapot, not able to brew coffee (RFC 2324).
  case imATeapot = 418
  /// Request misdirected to an incompatible server.
  case misdirectedRequest = 421
  /// Request is syntactically correct but unprocessable.
  case unprocessableContent = 422
  /// Resource is locked (WebDAV).
  case locked = 423
  /// Request failed due to dependency on another failed request (WebDAV).
  case failedDependency = 424
  /// Request received too early to process (RFC 8470).
  case tooEarly = 425
  /// Protocol upgrade required to process request.
  case upgradeRequired = 426
  /// Request must be conditional to prevent lost updates (RFC 6585).
  case preconditionRequired = 428
  /// Client has sent too many requests in a short period.
  case tooManyRequests = 429
  /// Request header fields too large to process.
  case requestHeaderFieldsTooLarge = 431
  /// Access denied due to legal reasons.
  case unavailableForLegalReasons = 451

  // 5xx Server Errors
  /// Generic server error.
  case internalServerError = 500
  /// Server does not recognize the request method.
  case notImplemented = 501
  /// Invalid response from an upstream server.
  case badGateway = 502
  /// Server unavailable due to overload or maintenance.
  case serviceUnavailable = 503
  /// Gateway or proxy timeout.
  case gatewayTimeout = 504
  /// HTTP version used in request not supported.
  case httpVersionNotSupported = 505
  /// Circular reference in content negotiation.
  case variantAlsoNegotiates = 506
  /// Server unable to store required representation.
  case insufficientStorage = 507
  /// Infinite loop detected during request processing.
  case loopDetected = 508
  /// Further extensions required for the request.
  case notExtended = 510
  /// Network authentication required to access resource.
  case networkAuthenticationRequired = 511

  // Enum for Categories
  public enum Category {
    case informational, success, redirection, clientError, serverError
  }

  /// Determines the category of the HTTP status code.
  public var category: Category {
    switch rawValue {
    case 100..<200: .informational
    case 200..<300: .success
    case 300..<400: .redirection
    case 400..<500: .clientError
    case 500..<600: .serverError
    default: fatalError("Invalid HTTP status code")
    }
  }
}

extension HTTPStatusCode: CustomStringConvertible {
  /// Returns a string representation of the HTTP status code with its name and number.
  public var description: String {
    switch self {
    case .ok: "OK (200)"
    case .created: "Created (201)"
    case .accepted: "Accepted (202)"
    case .nonAuthoritativeInformation: "Non-Authoritative Information (203)"
    case .noContent: "No Content (204)"
    case .resetContent: "Reset Content (205)"
    case .partialContent: "Partial Content (206)"
    case .multiStatus: "Multi-Status (207)"
    case .alreadyReported: "Already Reported (208)"
    case .imUsed: "IM Used (226)"
    case .multipleChoices: "Multiple Choices (300)"
    case .movedPermanently: "Moved Permanently (301)"
    case .found: "Found (302)"
    case .seeOther: "See Other (303)"
    case .notModified: "Not Modified (304)"
    case .useProxy: "Use Proxy (305)"
    case .temporaryRedirect: "Temporary Redirect (307)"
    case .permanentRedirect: "Permanent Redirect (308)"
    case .badRequest: "Bad Request (400)"
    case .unauthorized: "Unauthorized (401)"
    case .paymentRequired: "Payment Required (402)"
    case .forbidden: "Forbidden (403)"
    case .notFound: "Not Found (404)"
    case .methodNotAllowed: "Method Not Allowed (405)"
    case .notAcceptable: "Not Acceptable (406)"
    case .proxyAuthenticationRequired: "Proxy Authentication Required (407)"
    case .requestTimeout: "Request Timeout (408)"
    case .conflict: "Conflict (409)"
    case .gone: "Gone (410)"
    case .lengthRequired: "Length Required (411)"
    case .preconditionFailed: "Precondition Failed (412)"
    case .contentTooLarge: "Payload Too Large (413)"
    case .uriTooLong: "URI Too Long (414)"
    case .unsupportedMediaType: "Unsupported Media Type (415)"
    case .rangeNotSatisfiable: "Range Not Satisfiable (416)"
    case .expectationFailed: "Expectation Failed (417)"
    case .imATeapot: "I'm a Teapot (418)"
    case .misdirectedRequest: "Misdirected Request (421)"
    case .unprocessableContent: "Unprocessable Content (422)"
    case .locked: "Locked (423)"
    case .failedDependency: "Failed Dependency (424)"
    case .tooEarly: "Too Early (425)"
    case .upgradeRequired: "Upgrade Required (426)"
    case .preconditionRequired: "Precondition Required (428)"
    case .tooManyRequests: "Too Many Requests (429)"
    case .requestHeaderFieldsTooLarge: "Request Header Fields Too Large (431)"
    case .unavailableForLegalReasons: "Unavailable For Legal Reasons (451)"
    case .internalServerError: "Internal Server Error (500)"
    case .notImplemented: "Not Implemented (501)"
    case .badGateway: "Bad Gateway (502)"
    case .serviceUnavailable: "Service Unavailable (503)"
    case .gatewayTimeout: "Gateway Timeout (504)"
    case .httpVersionNotSupported: "HTTP Version Not Supported (505)"
    case .variantAlsoNegotiates: "Variant Also Negotiates (506)"
    case .insufficientStorage: "Insufficient Storage (507)"
    case .loopDetected: "Loop Detected (508)"
    case .notExtended: "Not Extended (510)"
    case .networkAuthenticationRequired: "Network Authentication Required (511)"
    default: "Unknown Status (\(rawValue))"
    }
  }
}

extension HTTPURLResponse {
  public var status: HTTPStatusCode? {
    HTTPStatusCode(rawValue: statusCode)
  }
}
