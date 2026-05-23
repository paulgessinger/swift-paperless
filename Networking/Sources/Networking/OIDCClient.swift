//
//  OIDCClient.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 11.01.26.
//

import AuthenticationServices
import Common
import MetaCodable
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

  public func login(provider: OIDCProvider, auth: WebAuthenticationSession) async throws -> String {
    logger.info("Initiating OIDC flow with provider \(provider.id, privacy: .public)")
    self.token = nil

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

    let apiToken = try await exchangeIdTokenWithPaperless(
      providerId: provider.id,
      clientId: provider.clientId,
      idToken: token.id_token,
      csrf: csrf
    )

    logger.debug("Have received Paperless api token: \(apiToken)")

    self.token = apiToken
    return apiToken
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
      struct SocialAccount: Decodable { let providers: [OIDCProvider] }
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
    providers = config.data.socialaccount.providers.filter { $0.supported }
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
  ) async throws -> String {
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
      let body = String(data: data, encoding: .utf8) ?? ""
      logger.error(
        "Paperless token exchange returned status \(http.statusCode): \(body, privacy: .private)"
      )
      throw OIDCError.paperlessTokenExchangeFailed(statusCode: http.statusCode, body: body)
    }

    let decoded = try JSONDecoder().decode(PaperlessTokenResponse.self, from: data)
    return decoded.meta.access_token
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

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct OIDCProvider: Decodable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let flows: [String]
  public let clientId: String
  public let openidConfigurationUrl: String?

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
  struct Meta: Decodable, Equatable { let access_token: String }
  let meta: Meta
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
}

extension OIDCError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .missingCSRF:
      "Server did not provide a CSRF token."
    case .missingScope:
      "Could not determine OIDC scope from the server's redirect response."
    case .missingCode:
      "OIDC provider did not return an authorization code."
    case .missingConfigurationURL:
      "OIDC provider does not advertise an OpenID configuration URL."
    case .invalidState:
      "OIDC callback returned an unexpected state value."
    case .authFailed:
      "Authentication with the OIDC provider failed."
    case .invalidURL:
      "Failed to construct a valid OIDC request URL."
    case .invalidRedirectURL:
      "The OIDC redirect URL is invalid."
    case .formBodyEncodingFailed:
      "Failed to encode the OIDC request body."
    case .tokenExchangeFailed(let error, let description):
      if let description {
        "OAuth2 token exchange failed: \(error) — \(description)"
      } else {
        "OAuth2 token exchange failed: \(error)"
      }
    case .paperlessTokenExchangeFailed(let statusCode, let body):
      if body.isEmpty {
        "Paperless rejected the OIDC id_token (HTTP \(statusCode))."
      } else {
        "Paperless rejected the OIDC id_token (HTTP \(statusCode)): \(body)"
      }
    }
  }
}
