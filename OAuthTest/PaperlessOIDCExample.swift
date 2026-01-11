import AuthenticationServices
import CryptoKit
import SwiftUI
import UIKit

struct ContentView: View {
  @Environment(\.webAuthenticationSession) private var auth
  @State private var client = PaperlessOIDCClient(baseURL: URL(string: "http://localhost:8000")!)

  var body: some View {
    VStack(spacing: 16) {
      Text(client.token ?? "idle").font(.footnote)
      Button("Login") { Task { try? await client.login(auth: auth) } }
    }
    .padding()
  }
}

@Observable
final class PaperlessOIDCClient {
  private let baseURL: URL
  private let session: URLSession

  private let callbackScheme = "x-oauth-text"
  private let redirectURI = "x-oauth-test://callback"

  private(set) var token: String? = nil

  init(baseURL: URL) {
    self.baseURL = baseURL
    let config = URLSessionConfiguration.default
    config.httpCookieStorage = .shared
    config.httpShouldSetCookies = true
    self.session = URLSession(configuration: config)
  }

  func login(auth: WebAuthenticationSession) async throws -> String {
    self.token = nil

    let csrf = try await fetchCSRF()
    let provider = try await fetchProvider()
    let scope = try await fetchScope(providerId: provider.id, csrf: csrf)
    guard let openidConfigurationUrl = URL(string: provider.openidConfigurationUrl) else {
      throw OIDCError.missingConfigurationURL
    }
    let discovery = try await fetchDiscovery(url: openidConfigurationUrl)

    let pkce = PKCE()
    let state = UUID().uuidString

    let authURL = try buildAuthorizationURL(
      authEndpoint: discovery.authorization_endpoint,
      clientId: provider.clientId,
      redirectURI: redirectURI,
      scope: scope,
      state: state,
      pkce: pkce
    )

    let callback = try await auth.authenticate(
      using: authURL,
      callbackURLScheme: callbackScheme
    )

    let params = queryParams(from: callback)

    guard params["state"] == state else { throw OIDCError.invalidState }
    guard let code = params["code"] else { throw OIDCError.missingCode }

    let token = try await exchangeCode(
      tokenEndpoint: discovery.token_endpoint,
      clientId: provider.clientId,
      code: code,
      redirectURI: redirectURI,
      pkce: pkce
    )

    let apiToken = try await exchangeIdTokenWithPaperless(
      providerId: provider.id,
      clientId: provider.clientId,
      idToken: token.id_token,
      csrf: csrf
    )

    self.token = apiToken
    return apiToken
  }

  private func fetchCSRF() async throws -> String {
    _ = try await session.data(from: baseURL.appendingPathComponent("accounts/login"))
    let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
    guard let csrf = cookies.first(where: { $0.name == "csrftoken" })?.value else {
      throw OIDCError.missingCSRF
    }
    return csrf
  }

  private func fetchProvider() async throws -> Provider {
    guard let url = URL(string: "_allauth/app/v1/config", relativeTo: baseURL) else {
      throw OIDCError.invalidURL
    }
    let (data, _) = try await session.data(from: url)
    let config = try JSONDecoder().decode(HeadlessConfig.self, from: data)
    return config.data.socialaccount.providers[0]
  }

  private func fetchScope(providerId: String, csrf: String) async throws -> String {
    guard let url = URL(string: "_allauth/browser/v1/auth/provider/redirect", relativeTo: baseURL)
    else {
      throw OIDCError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
    request.httpBody = formBody([
      "provider": providerId,
      "callback_url": "http://localhost:8000/",
      "process": "login",
      "csrfmiddlewaretoken": csrf,
    ])

    let (_, response) = try await session.data(for: request, delegate: NoRedirectDelegate())
    let http = response as? HTTPURLResponse
    guard let location = http?.value(forHTTPHeaderField: "Location"),
      let scope = URLComponents(string: location)?.queryItems?.first(where: { $0.name == "scope" })?
        .value
    else {
      throw OIDCError.missingScope
    }
    return scope
  }

  private func fetchDiscovery(url: URL) async throws -> OIDCDiscovery {
    let (data, _) = try await session.data(from: url)
    return try JSONDecoder().decode(OIDCDiscovery.self, from: data)
  }

  private func exchangeCode(
    tokenEndpoint: URL,
    clientId: String,
    code: String,
    redirectURI: String,
    pkce: PKCE
  ) async throws -> TokenResponse {
    var request = URLRequest(url: tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = formBody([
      "grant_type": "authorization_code",
      "client_id": clientId,
      "code": code,
      "redirect_uri": redirectURI,
      "code_verifier": pkce.verifier,
    ])
    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(TokenResponse.self, from: data)
  }

  private func exchangeIdTokenWithPaperless(
    providerId: String,
    clientId: String,
    idToken: String,
    csrf: String
  ) async throws -> String {
    guard let url = URL(string: "_allauth/app/v1/auth/provider/token", relativeTo: baseURL) else {
      throw OIDCError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
    let payload: [String: Any] = [
      "provider": providerId,
      "process": "login",
      "token": ["client_id": clientId, "id_token": idToken],
      "csrfmiddlewaretoken": csrf,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
    let (data, _) = try await session.data(for: request)
    let response = try JSONDecoder().decode(PaperlessTokenResponse.self, from: data)
    return response.meta.access_token
  }

  private func buildAuthorizationURL(
    authEndpoint: URL,
    clientId: String,
    redirectURI: String,
    scope: String,
    state: String,
    pkce: PKCE
  ) throws(OIDCError) -> URL {
    var comps = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
    comps.queryItems = [
      .init(name: "client_id", value: clientId),
      .init(name: "redirect_uri", value: redirectURI),
      .init(name: "response_type", value: "code"),
      .init(name: "scope", value: scope),
      .init(name: "state", value: state),
      .init(name: "code_challenge", value: pkce.challenge),
      .init(name: "code_challenge_method", value: "S256"),
    ]
    guard let url = comps.url else {
      throw .invalidURL
    }
    return url
  }

  private func formBody(_ params: [String: String]) -> Data {
    params.map {
      let key = $0.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.key
      let value =
        $0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value
      return "\(key)=\(value)"
    }
    .joined(separator: "&")
    .data(using: .utf8) ?? Data()
  }

  private func queryParams(from url: URL) -> [String: String] {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?
      .reduce(into: [:]) { $0[$1.name] = $1.value } ?? [:]
  }
}

struct HeadlessConfig: Decodable {
  struct DataContainer: Decodable { let socialaccount: SocialAccount }
  struct SocialAccount: Decodable { let providers: [Provider] }
  let data: DataContainer
}

struct Provider: Decodable {
  let id: String
  let clientId: String
  let openidConfigurationUrl: String
  enum CodingKeys: String, CodingKey {
    case id
    case clientId = "client_id"
    case openidConfigurationUrl = "openid_configuration_url"
  }
}

struct OIDCDiscovery: Decodable {
  let authorization_endpoint: URL
  let token_endpoint: URL
}

struct TokenResponse: Decodable {
  let id_token: String
}

struct PaperlessTokenResponse: Decodable {
  struct Meta: Decodable { let access_token: String }
  let meta: Meta
}

struct PKCE {
  let verifier: String
  let challenge: String

  init() {
    verifier = PKCE.randomBase64URL(length: 48)
    challenge = PKCE.sha256Base64URL(verifier)
  }

  static func randomBase64URL(length: Int) -> String {
    let bytes = (0..<length).map { _ in UInt8.random(in: 0...255) }
    return Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func sha256Base64URL(_ input: String) -> String {
    let hash = SHA256.hash(data: Data(input.utf8))
    return Data(hash).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

enum OIDCError: Error {
  case missingCSRF
  case missingScope
  case missingCode
  case missingConfigurationURL
  case invalidState
  case authFailed
  case invalidURL
}

@main
struct PaperlessOIDCExampleApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
