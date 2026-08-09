//
//  OIDCClient.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 11.01.26.
//

import AuthenticationServices
import Common
import SwiftUI
import os

@Observable
@MainActor
@available(macOS 14.0, *)
public final class OIDCClient {
  static let urlFragment = "api/auth/headless"

  private let baseURL: URL
  private let session: URLSession
  private let redirectURI: URL
  private let callbackScheme: String

  public private(set) var token: String? = nil

  /// Session token captured when Paperless required a second factor (TOTP) to
  /// finish the OIDC login. It is sent back as the `x-session-token` header when
  /// confirming the code via `confirmMFA(code:)`.
  var pendingMFASessionToken: String?

  public private(set) var providers: [OIDCProvider] = []

  private let logger = Logger(subsystem: "com.paulgessinger.swift-paperless", category: "OIDC")

  public init(baseURL: URL, redirectURI: URL, session: URLSession? = nil) throws(OIDCError) {
    self.baseURL = baseURL

    self.redirectURI = redirectURI

    guard let components = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false),
      let scheme = components.scheme
    else {
      throw .invalidRedirectURL
    }

    self.callbackScheme = scheme

    if let session {
      self.session = session
    } else {
      let config = URLSessionConfiguration.default
      config.httpCookieStorage = .shared
      config.httpShouldSetCookies = true
      self.session = URLSession(configuration: config)
    }
  }

  public func login(
    provider: OIDCProvider, auth: WebAuthenticationSession
  ) async throws -> OIDCLoginResult {
    logger.info("Initiating OIDC flow with provider \(provider.id, privacy: .public)")
    self.token = nil
    self.pendingMFASessionToken = nil

    // Paperless-ngx requires us to go through CSRF protection to talk to the allauth headless endpoints
    let csrf = try await fetchCSRF()
    logger.debug("Received CSRF token: \(csrf)")

    let scope = try await fetchScope(providerId: provider.id, csrf: csrf)
    logger.debug("Received scope: \(scope, privacy: .public)")

    guard let openidConfigurationUrl = provider.openidConfigurationUrl,
      let oidcURL = URL(string: openidConfigurationUrl)
    else {
      throw OIDCError.missingConfigurationURL
    }

    logger.debug("OIDC configuation url: \(oidcURL)")

    let discovery = try await fetchDiscovery(url: oidcURL)
    logger.debug(
      "OIDC discovery: authorization = \(discovery.authorization_endpoint), token = \(discovery.token_endpoint)"
    )

    let pkce = PKCE()
    let state = UUID().uuidString

    let authURL = try buildAuthorizationURL(
      authEndpoint: discovery.authorization_endpoint,
      clientId: provider.clientId,
      scope: scope,
      state: state,
      pkce: pkce
    )

    logger.debug("Authorization URL is \(authURL), launching user authentication flow")
    let callback = try await auth.authenticate(
      using: authURL,
      callbackURLScheme: callbackScheme
    )

    logger.debug("User authentication returned callback url: \(callback)")

    let params = queryParams(from: callback)
    logger.debug("Extracting parameters from callback url: \(params)")

    guard params["state"] == state else {
      logger.error(
        "Parameter state \(String(describing: params["state"])) is not the expected state \(state)")
      throw OIDCError.invalidState
    }
    guard let code = params["code"] else {
      logger.error("Callback did not contain code")
      throw OIDCError.missingCode
    }

    let token = try await exchangeCode(
      tokenEndpoint: discovery.token_endpoint,
      clientId: provider.clientId,
      code: code,
      pkce: pkce
    )

    logger.debug("Have received OIDC token from provider: \(token.id_token)")

    let result = try await exchangeIdTokenWithPaperless(
      providerId: provider.id,
      clientId: provider.clientId,
      idToken: token.id_token,
      csrf: csrf
    )

    switch result {
    case .success(let apiToken):
      logger.debug("Have received Paperless api token: \(apiToken)")
      self.token = apiToken
      return .success(token: apiToken)

    case .mfaRequired(let sessionToken):
      logger.info(
        "Paperless requires a second factor (TOTP) to complete the OIDC login")
      self.pendingMFASessionToken = sessionToken
      return .mfaRequired
    }
  }

  /// Confirm a second factor (TOTP) code for an OIDC login that was suspended
  /// with `.mfaRequired`. Posts the code to allauth's `2fa/authenticate`
  /// endpoint using the pending session token captured during the login, and
  /// returns the Paperless API token once the code is accepted.
  public func confirmMFA(code: String) async throws -> String {
    logger.info("Confirming MFA code with Paperless")
    guard let sessionToken = pendingMFASessionToken else {
      logger.error("No pending MFA session to confirm against")
      throw OIDCError.mfaSessionMissing
    }

    guard
      let url = URL(
        string: "\(Self.urlFragment)/app/v1/auth/2fa/authenticate", relativeTo: baseURL)
    else {
      logger.error("Failed to build 2fa/authenticate url")
      throw OIDCError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(sessionToken, forHTTPHeaderField: "x-session-token")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])

    let (data, response) = try await session.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      logger.error("2fa/authenticate response was not an HTTP response")
      throw OIDCError.paperlessTokenExchangeFailed(
        statusCode: 0, body: String(data: data, encoding: .utf8) ?? "")
    }

    switch http.statusCode {
    case 200..<300:
      let decoded = try JSONDecoder().decode(PaperlessTokenResponse.self, from: data)
      guard let apiToken = decoded.meta?.access_token else {
        logger.error("2fa/authenticate succeeded but no access_token in meta")
        throw OIDCError.paperlessTokenExchangeFailed(
          statusCode: http.statusCode,
          body: String(data: data, encoding: .utf8) ?? "")
      }
      logger.debug("Have received Paperless api token after MFA: \(apiToken)")
      self.token = apiToken
      return apiToken

    case 400:
      if let errorResponse = try? JSONDecoder().decode(OIDCErrorResponse.self, from: data),
        errorResponse.errors?.contains(where: { $0.code == "incorrect_code" }) == true
      {
        logger.info("Paperless rejected the MFA code")
        throw OIDCError.invalidCode
      }
      let body = String(data: data, encoding: .utf8) ?? ""
      logger.error("MFA code confirm returned 400: \(body, privacy: .private)")
      throw OIDCError.paperlessTokenExchangeFailed(statusCode: 400, body: body)

    case 401:
      // The pending login session is gone (expired or already consumed).
      logger.error("Pending MFA session is no longer valid (401)")
      throw OIDCError.mfaSessionExpired

    default:
      let body = String(data: data, encoding: .utf8) ?? ""
      logger.error(
        "MFA code confirm returned \(http.statusCode): \(body, privacy: .private)")
      throw OIDCError.paperlessTokenExchangeFailed(statusCode: http.statusCode, body: body)
    }
  }

  private func fetchCSRF() async throws -> String {
    logger.info("Fetching CSRF cookie")
    _ = try await session.data(from: baseURL.appendingPathComponent("accounts/login"))
    let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
    guard let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value else {
      logger.error("Response to login request did not contain a CSRF token")
      throw OIDCError.missingCSRF
    }
    return csrf
  }

  public func fetchProviders() async throws {
    logger.info("Fetching providers")
    guard let url = URL(string: "\(Self.urlFragment)/app/v1/config", relativeTo: baseURL) else {
      logger.error("Failed to build config url")
      throw OIDCError.invalidURL
    }

    struct HeadlessConfig: Decodable {
      struct DataContainer: Decodable { let socialaccount: SocialAccount }
      struct SocialAccount: Decodable { let providers: [ApiOIDCProvider] }
      let data: DataContainer
    }

    let (data, _) = try await session.data(from: url)

    let config: HeadlessConfig
    do {
      config = try JSONDecoder().decode(HeadlessConfig.self, from: data)
    } catch {
      logger.info(
        "Unable to decode response from provider config endpoint. This likely means the endpoint is not available: \(error)"
      )
      return
    }
    providers = config.data.socialaccount.providers.map(\.domain).filter(\.supported)
  }

  func fetchScope(providerId: String, csrf: String) async throws -> String {
    logger.info("Fetching scope from redirect")
    guard
      let url = URL(
        string: "\(Self.urlFragment)/browser/v1/auth/provider/redirect", relativeTo: baseURL)
    else {
      logger.error("Failed to build provider redirect url")
      throw OIDCError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
    setRefererHeader(on: &request)
    request.httpBody = try formBody([
      "provider": providerId,
      "callback_url": baseURL.absoluteString,
      "process": "login",
      "csrfmiddlewaretoken": csrf,
    ])

    let (_, response) = try await session.data(for: request, delegate: NoRedirectDelegate())

    guard let http = response as? HTTPURLResponse else {
      logger.error("Redirect response is not HTTPURLRespone")
      throw OIDCError.missingScope
    }

    guard let location = http.value(forHTTPHeaderField: "Location")
    else {
      logger.error("Redirect response does not contain Location header")
      throw OIDCError.missingScope
    }

    guard
      let scope = URLComponents(string: location)?.queryItems?.first(where: { $0.name == "scope" })?
        .value
    else {
      logger.error("Redirect response location header did not include scope query parameter")
      throw OIDCError.missingScope
    }
    return scope
  }

  private func fetchDiscovery(url: URL) async throws -> OIDCDiscovery {
    logger.info("Fetching discovery from url \(url)")
    let (data, _) = try await session.data(from: url)
    return try JSONDecoder().decode(OIDCDiscovery.self, from: data)
  }

  func exchangeCode(
    tokenEndpoint: URL,
    clientId: String,
    code: String,
    pkce: PKCE
  ) async throws -> TokenResponse {
    logger.info("Exchanging code with oidc token")
    var request = URLRequest(url: tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = try formBody([
      "grant_type": "authorization_code",
      "client_id": clientId,
      "code": code,
      "redirect_uri": redirectURI.absoluteString,
      "code_verifier": pkce.verifier,
    ])
    let (data, response) = try await session.data(for: request)

    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      logger.error(
        "Token endpoint returned status \(http.statusCode), attempting to decode OAuth2 error"
      )
      if let oauth = try? JSONDecoder().decode(OAuth2ErrorResponse.self, from: data) {
        throw OIDCError.tokenExchangeFailed(
          error: oauth.error, description: oauth.error_description)
      }
      let body = String(data: data, encoding: .utf8) ?? ""
      throw OIDCError.tokenExchangeFailed(
        error: "http_\(http.statusCode)", description: body.isEmpty ? nil : body)
    }

    return try JSONDecoder().decode(TokenResponse.self, from: data)
  }

  func exchangeIdTokenWithPaperless(
    providerId: String,
    clientId: String,
    idToken: String,
    csrf: String
  ) async throws -> PaperlessTokenExchangeResult {
    guard
      let url = URL(string: "\(Self.urlFragment)/app/v1/auth/provider/token", relativeTo: baseURL)
    else {
      logger.error("Failed to construct URL for obtaining Paperless token")
      throw OIDCError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
    setRefererHeader(on: &request)
    let payload: [String: Any] = [
      "provider": providerId,
      "process": "login",
      "token": ["client_id": clientId, "id_token": idToken],
      "csrfmiddlewaretoken": csrf,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
    let (data, response) = try await session.data(for: request)

    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      // A 401 carrying a pending `mfa_authenticate` flow means the login was
      // accepted but a second factor (TOTP) is required to finish it. The
      // session token lets us continue via `confirmMFA(code:)`.
      if http.statusCode == 401,
        let decoded = try? JSONDecoder().decode(PaperlessTokenResponse.self, from: data),
        decoded.data?.flows?.contains(where: {
          $0.id == "mfa_authenticate" && $0.is_pending == true
        }) == true,
        let sessionToken = decoded.meta?.session_token
      {
        logger.info("Paperless token exchange requires MFA (TOTP) to continue")
        return .mfaRequired(sessionToken: sessionToken)
      }

      let body = String(data: data, encoding: .utf8) ?? ""
      logger.error(
        "Paperless token exchange returned status \(http.statusCode): \(body, privacy: .private)"
      )
      throw OIDCError.paperlessTokenExchangeFailed(statusCode: http.statusCode, body: body)
    }

    let decoded = try JSONDecoder().decode(PaperlessTokenResponse.self, from: data)
    guard let apiToken = decoded.meta?.access_token else {
      logger.error("Token response did not contain an access token")
      throw OIDCError.paperlessTokenExchangeFailed(
        statusCode: 200, body: String(data: data, encoding: .utf8) ?? "")
    }
    return .success(token: apiToken)
  }

  private func buildAuthorizationURL(
    authEndpoint: URL,
    clientId: String,
    scope: String,
    state: String,
    pkce: PKCE
  ) throws(OIDCError) -> URL {
    var comps = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
    comps.queryItems = [
      .init(name: "client_id", value: clientId),
      .init(name: "redirect_uri", value: redirectURI.absoluteString),
      .init(name: "response_type", value: "code"),
      .init(name: "scope", value: scope),
      .init(name: "state", value: state),
      .init(name: "code_challenge", value: pkce.challenge),
      .init(name: "code_challenge_method", value: "S256"),
    ]
    guard let url = comps.url else {
      logger.error("Invalid URL after constructing authorization request")
      throw .invalidURL
    }
    return url
  }

  private func formBody(_ params: [String: String]) throws(OIDCError) -> Data {
    let data = params.map {
      let key = $0.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.key
      let value =
        $0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value
      return "\(key)=\(value)"
    }
    .joined(separator: "&")
    .data(using: .utf8)

    guard let data else {
      logger.error("Failed to build form body from params \(params)")
      throw .formBodyEncodingFailed
    }

    return data
  }

  private func queryParams(from url: URL) -> [String: String] {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?
      .reduce(into: [:]) { $0[$1.name] = $1.value } ?? [:]
  }

  // Django's CSRF middleware rejects HTTPS POSTs that carry neither an `Origin`
  // nor a `Referer` header, even when the CSRF token itself is valid (it falls
  // back to "strict referer checking" for secure requests). URLSession does not
  // set either header on programmatic requests, so we add `Referer` ourselves to
  // satisfy the same-origin check. See issue #559.
  private func setRefererHeader(on request: inout URLRequest) {
    request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
  }
}

private struct ApiOIDCProvider: Decodable, Sendable {
  let id: String
  let name: String
  let flows: [String]
  let client_id: String
  let openid_configuration_url: String?
}

extension ApiOIDCProvider {
  var domain: OIDCProvider {
    OIDCProvider(
      id: id,
      name: name,
      flows: flows,
      clientId: client_id,
      openidConfigurationUrl: openid_configuration_url
    )
  }
}

public struct OIDCProvider: Identifiable, Sendable {
  public let id: String
  public let name: String
  public let flows: [String]
  public let clientId: String
  public let openidConfigurationUrl: String?

  public init(
    id: String,
    name: String,
    flows: [String],
    clientId: String,
    openidConfigurationUrl: String?
  ) {
    self.id = id
    self.name = name
    self.flows = flows
    self.clientId = clientId
    self.openidConfigurationUrl = openidConfigurationUrl
  }

  public var supported: Bool {
    flows.contains("provider_redirect") && flows.contains("provider_token")
      && openidConfigurationUrl != nil
  }

  public var iconURL: URL? {
    get async {
      guard let oidcUrl = openidConfigurationUrl, var comp = URLComponents(string: oidcUrl) else {
        return nil
      }
      comp.path = ""
      comp.queryItems = [URLQueryItem]()
      guard let url = comp.url else {
        return nil
      }

      return await fetchFavicon(from: url)
    }
  }
}

private
  struct OIDCDiscovery: Decodable
{
  let authorization_endpoint: URL
  let token_endpoint: URL
}

struct TokenResponse: Decodable, Equatable {
  let id_token: String
}

// Per RFC 6749 §5.2 — OAuth 2.0 token endpoint error envelope.
struct OAuth2ErrorResponse: Decodable, Equatable {
  let error: String
  let error_description: String?
}

struct PaperlessTokenResponse: Decodable, Equatable {
  struct Meta: Decodable, Equatable {
    let access_token: String?
    let session_token: String?
  }
  struct Data: Decodable, Equatable {
    struct Flow: Decodable, Equatable {
      let id: String
      let is_pending: Bool?
    }
    let flows: [Flow]?
  }
  let meta: Meta?
  let data: Data?
}

/// Error envelope used by allauth headless responses (e.g. the 400 returned
/// when an MFA code is rejected).
struct OIDCErrorResponse: Decodable, Equatable {
  struct Item: Decodable, Equatable {
    let code: String
    let message: String?
  }
  let errors: [Item]?
}

private
  final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate
{
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

// User-facing, localized descriptions are provided by the app layer (see
// `OIDCError+LocalizedError.swift`), consistent with how `RequestError` is
// handled — the Networking package itself stays free of localized strings.
public enum OIDCError: Error, Equatable {
  case missingCSRF
  case missingScope
  case missingCode
  case missingConfigurationURL
  case invalidState
  case authFailed
  case invalidURL
  case invalidRedirectURL
  case formBodyEncodingFailed
  case tokenExchangeFailed(error: String, description: String?)
  case paperlessTokenExchangeFailed(statusCode: Int, body: String)
  /// The submitted MFA (TOTP) code was rejected by Paperless.
  case invalidCode
  /// An MFA step was expected but no pending login session was available.
  case mfaSessionMissing
  /// The pending MFA login session expired before the code was confirmed.
  case mfaSessionExpired
}

/// Result of an OIDC login attempt. `.mfaRequired` means the login was
/// accepted by Paperless but a second factor (TOTP) still needs to be
/// confirmed via `OIDCClient.confirmMFA(code:)`.
public enum OIDCLoginResult: Equatable, Sendable {
  case success(token: String)
  case mfaRequired
}

enum PaperlessTokenExchangeResult: Equatable {
  case success(token: String)
  case mfaRequired(sessionToken: String)
}
