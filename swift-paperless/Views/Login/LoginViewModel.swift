//
//  LoginViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 31.07.2024.
//

import AuthenticationServices
import Common
import DataModel
import Foundation
import Networking
import Nuke
import SwiftUI
import os

enum LoginState: Equatable {
  case empty
  case checking
  case valid
  case error(_: LoginError)
}

enum CredentialMode: Equatable, Hashable, CaseIterable {
  case usernameAndPassword
  case token
  case none
  case oidc

  var label: String {
    let res: LocalizedStringResource =
      switch self {
      case .usernameAndPassword: .login(.credentialModeUsernamePassword)
      case .token: .login(.credentialModeToken)
      case .none: .login(.credentialModeNone)
      case .oidc: .login(.credentialModeOidc)
      }
    return String(localized: res)
  }

  var description: Text {
    switch self {
    case .usernameAndPassword:
      Text(.login(.credentialModeUsernamePasswordDescription))
    case .token:
      Text(.login(.credentialModeTokenDescription))
    case .none:
      Text(.login(.credentialModeNoneDescription))
    case .oidc:
      Text(.login(.credentialModeOidcDescription(DocumentationLinks.oidc.absoluteString)))
    }
  }
}

enum CredentialState: Equatable {
  case none
  case validating
  case valid
  case error(LoginError)
}

@MainActor
@Observable
class LoginViewModel {
  var loginState = LoginState.empty

  var loginStateValid: Bool {
    switch loginState {
    case .valid, .error:  // Error is technically not valid, but we want to allow retrying
      true
    default:
      false
    }
  }

  var extraHeaders: [Connection.HeaderValue] = []

  var selectedIdentity: TLSIdentity?

  var url: String = ""

  var checkUrlTask: Task<Void, Never>?

  enum Scheme: String {
    case http
    case https

    var label: String {
      "\(self)://"
    }
  }

  var scheme = Scheme.https

  var credentialMode = CredentialMode.usernameAndPassword
  var credentialState = CredentialState.none

  // Display OTP input field
  var otpEnabled = false
  var otp: String = ""

  // For user password login
  var username: String = ""
  var password: String = ""

  // for token login
  var token: String = ""

  var oidcClient: OIDCClient?

  @ObservationIgnored
  let imagePipeline = ImagePipeline()
  @ObservationIgnored
  let imagePrefetcher: ImagePrefetcher

  init() {
    imagePrefetcher = ImagePrefetcher(pipeline: imagePipeline)

    imagePrefetcher.didComplete = {
      Logger.shared.debug("LoginViewModel prefetching completes")
    }
  }

  // - MARK: Methods

  func onChangeUrl(immediate: Bool = false) {
    checkUrlTask?.cancel()
    oidcClient = nil

    guard !url.isEmpty else {
      loginState = .empty
      return
    }

    checkUrlTask = Task {
      loginState = .checking
      if !immediate {
        do {
          try await Task.sleep(for: .seconds(1.0))
        } catch {
          return
        }
      }

      if !url.isEmpty {
        await checkUrl(string: fullUrl)
      }
    }

    if url.starts(with: "https://") {
      scheme = .https
      url.replace(/^https:\/\//, with: "")
    }

    if url.starts(with: "http://") {
      scheme = .http
      url.replace(/^http:\/\//, with: "")
    }
  }

  private func decodeDetails(_ body: Data) -> String? {
    let raw = String(data: body, encoding: .utf8)
    Logger.shared.info("Decoding details from response: \(raw ?? "no data", privacy: .public)")
    struct Response: Decodable {
      var detail: String?
      var non_field_errors: [String]
    }
    var results = [String]()
    do {
      let response = try JSONDecoder().decode(Response.self, from: body)
      if let detail = response.detail {
        results.append(detail)
      }

      results.append(
        contentsOf: response.non_field_errors.map {
          $0.hasSuffix(".") ? $0 : "\($0)."
        })
    } catch is DecodingError {
      // Recover error message if decoding fails
      if let raw {
        results.append(raw)
      }
    } catch {
      // Not much we can do here.
    }

    if results.isEmpty {
      return nil
    } else {
      return results.joined(separator: " ")
    }
  }

  func checkUrl(string value: String) async {
    Logger.shared.notice("Checking backend URL \(value)")
    guard !value.isEmpty else {
      Logger.shared.notice("Value is empty")
      loginState = .empty
      return
    }

    let apiUrl: URL
    let tokenUrl: URL

    do throws(UrlError) {
      (apiUrl, tokenUrl) = try deriveUrl(string: fullUrl, suffix: "token")
    } catch {
      Logger.shared.error("Cannot derive URL: \(value) -> \(error)")
      loginState = .error(.invalidUrl(error))
      return
    }

    var request = URLRequest(url: tokenUrl)
    extraHeaders.apply(toRequest: &request)
    request.timeoutInterval = 15
    request.setValue(
      "application/json; version=\(ApiRepository.minimumApiVersion)", forHTTPHeaderField: "Accept")

    Logger.api.info("Headers for check request: \(request.allHTTPHeaderFields ?? [:])")

    do {
      Logger.shared.info("Checking valid-looking URL \(apiUrl)")
      loginState = .checking
      let selectedIdentity = selectedIdentity
      Logger.shared.info("Using identity: \(selectedIdentity?.name ?? "none")")

      let session = URLSession(
        configuration: .default,
        delegate: PaperlessURLSessionDelegate(identity: selectedIdentity),
        delegateQueue: nil)

      let (data, response) = try await session.getData(for: request)

      guard let httpResponse = response as? HTTPURLResponse, let status = httpResponse.status else {
        loginState = .error(.request(.invalidResponse))
        return
      }

      // As per https://github.com/paperless-ngx/paperless-ngx/pull/8948#issuecomment-2661515625, a 405 indicates the version is ok, but the method is not allowed
      guard status == .methodNotAllowed else {
        let detail = decodeDetails(data)
        Logger.shared.warning(
          "Checking API status was not 200 but \(status.rawValue, privacy: .public), detail: \(detail ?? "no detail", privacy: .public)"
        )
        switch status {
        case .notAcceptable:
          loginState = .error(.request(.unsupportedVersion))
        default:
          loginState = .error(
            .request(
              .unexpectedStatusCode(
                code: status,
                detail: detail)))
        }
        return
      }

      loginState = .valid

      await makeOIDCClient()
    } catch let error where error.isCancellationError {
      // do nothing
      return
    } catch let error as NSError where LoginViewModel.isLocalNetworkDenied(error) {
      // @TODO: Handle these cases in a `RequestError` factory or init func
      // @TODO: Check error domain in this case
      Logger.shared.error("Unable to connect to API: local network access denied")
      loginState = .error(.request(.localNetworkDenied))
    } catch let nsError as NSError where nsError.domain == NSURLErrorDomain {
      if let error = RequestError(from: nsError) {
        Logger.shared.error(
          "Checking API converted NSError \(nsError) to known error: \(String(describing: error))")
        loginState = .error(.request(error))
      } else {
        Logger.shared.error("Checking API unknown NSError: \(nsError)")
        loginState = .error(LoginError(other: nsError))
        return
      }
    } catch {
      Logger.shared.error("Checking API error: \(error)")
      loginState = .error(LoginError(other: error))
      return
    }
  }

  private func makeOIDCClient() async {
    let fullUrl = fullUrl
    Logger.shared.info("Making OIDC client with url \(fullUrl)")
    let baseUrl: URL
    do {
      (baseUrl, _) = try deriveUrl(string: fullUrl, suffix: "token")
    } catch {
      Logger.shared.error("Failed to derive URL for OIDC client: \(error)")
      return
    }

    let client: OIDCClient
    do {
      let redirectURI = #URL("x-paperless://oidc-callback")
      client = try OIDCClient(baseURL: baseUrl, redirectURI: redirectURI)
    } catch {
      Logger.shared.error("Failed to build OIDC client: \(error, privacy: .public)")
      return
    }

    oidcClient = client

    do {
      try await client.fetchProviders()
      Logger.shared.info("Have providers: \(client.providers)")

      await prefetchOIDCProviderIcons()
    } catch {
      Logger.shared.error("Failed to fetch OIDC providers: \(error, privacy: .public)")
    }

  }

  private func prefetchOIDCProviderIcons() async {
    guard let client = oidcClient, !client.providers.isEmpty else {
      return
    }

    Logger.shared.debug("Prefetching icons for \(client.providers.count) providers")

    let icons = await withTaskGroup(returning: [URL].self) { group in
      for provider in client.providers {
        group.addTask { await provider.iconURL }
      }

      var icons: [URL] = []
      for await task in group {
        if let url = task {
          icons.append(url)
        }
      }
      return icons
    }

    imagePrefetcher.startPrefetching(with: icons)
  }

  // @TODO: Centralize this to RequestError
  nonisolated
    static func isLocalNetworkDenied(_ error: NSError) -> Bool
  {
    Logger.shared.debug("Checking API NSError: \(error)")

    if #available(iOS 19.0, *) {
      // iOS 26 presents (apparently) as iOS 19 on the old SDK
      return false
    } else {
      guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
        return false
      }
      Logger.shared.debug("Checking API underlying NSError: \(underlying)")

      guard
        let reason = (underlying.userInfo["_NSURLErrorNWPathKey"] as? NSObject)?.value(
          forKey: "reason") as? Int
      else {
        return false
      }

      Logger.shared.debug("Unsatisfied reason code is: \(reason)")
      return reason == 29
    }
  }

  var fullUrl: String {
    "\(scheme)://\(url)"
  }

  var isLocalAddress: Bool {
    Self.isLocalAddress(fullUrl)
  }

  nonisolated
    static func isLocalAddress(_ url: String) -> Bool
  {
    guard let components = URLComponents(string: url), let host = components.host else {
      return false
    }

    if host == "localhost" {
      return true
    }

    guard let match = try? /(\d+)\.(\d+)\.(\d+)\.(\d+)/.wholeMatch(in: host) else {
      return false
    }

    let ip = (UInt(match.1)!, UInt(match.2)!, UInt(match.3)!, UInt(match.4)!)

    if ip == (127, 0, 0, 1) {
      return true
    }

    return (ip >= (10, 0, 0, 0) && ip <= (10, 255, 255, 255))
      || (ip >= (172, 16, 0, 0) && ip <= (172, 31, 255, 255))
      || (ip >= (192, 168, 0, 0) && ip <= (192, 168, 255, 255))
  }

  private static func isMFAFailure(body: Data) -> Bool {
    Logger.shared.info(
      "Checking for MFA failure from response: \(String(data: body, encoding: .utf8) ?? "no data", privacy: .public)"
    )
    struct Response: Decodable {
      var non_field_errors: [String]
    }

    guard let response = try? JSONDecoder().decode(Response.self, from: body) else {
      return false
    }

    guard let error = response.non_field_errors.first else {
      return false
    }

    let mfaSentinel = "MFA code is required"

    return error == mfaSentinel
  }

  private func fetchToken(url tokenUrl: URL) async throws(LoginError) -> String {
    let username = username
    let password = password
    Logger.shared.info("Fetching token from username \(username) and password \(password)")

    struct TokenRequest: Encodable {
      var username: String
      var password: String
      var code: String?
    }

    let json: Data
    do {
      json = try JSONEncoder().encode(
        TokenRequest(username: username, password: password, code: otpEnabled ? otp : nil))
    } catch {
      // This should never ever happen
      Logger.shared.error("Unable to encode TokenRequest, this is an internal error")
      fatalError("Unable to encode TokenRequest, this is an internal error")
    }

    var request = URLRequest(url: tokenUrl)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = json
    extraHeaders.apply(toRequest: &request)

    let headerStr = sanitize(headers: request.allHTTPHeaderFields)
    Logger.shared.info("Sending login request with headers: \(headerStr, privacy: .public)")

    let session = URLSession(
      configuration: .default, delegate: PaperlessURLSessionDelegate(identity: selectedIdentity),
      delegateQueue: nil)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.getData(for: request)
    } catch {
      throw LoginError(other: error)
    }

    guard let response = response as? HTTPURLResponse, let status = response.status else {
      throw LoginError.request(.invalidResponse)
    }

    switch status {
    case .ok:
      break
    case .badRequest:
      let details = decodeDetails(data)
      Logger.shared.error(
        "Credentials were rejected when requesting token: \(details ?? "no details", privacy: .public)"
      )
      // @TODO: Add check for invalid MFA code maybe?
      if Self.isMFAFailure(body: data) {
        Logger.shared.info("Detected MFA failure, show OTP code input field")
        throw LoginError.otpRequired
      } else {
        throw LoginError.invalidLogin(detail: details)
      }
    default:
      let details = decodeDetails(data)
      Logger.shared.error(
        "Token request response was not 200 but \(status.rawValue, privacy: .public), detail: \(details ?? "no details", privacy: .public)"
      )
      throw LoginError.request(
        .unexpectedStatusCode(
          code: status,
          detail: details))
    }

    struct TokenResponse: Decodable {
      var token: String
    }

    do {
      let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
      return tokenResponse.token
    } catch {
      Logger.shared.error("Token response could not be decoded, even though status code was good")
      throw LoginError.request(.invalidResponse)
    }
  }

  func validateCredentials(auth: WebAuthenticationSession? = nil, provider: OIDCProvider? = nil)
    async -> StoredConnection?
  {
    let fullUrl = fullUrl
    Logger.shared.info("Validating credentials against url: \(fullUrl)")
    credentialState = .validating

    let baseUrl: URL
    let tokenUrl: URL
    do throws(UrlError) {
      (baseUrl, tokenUrl) = try deriveUrl(string: fullUrl, suffix: "token")
    } catch {
      // In principle this is checked before, so should not fail here
      Logger.shared.warning("Error making URL for logging in (url: \(fullUrl)) \(error)")
      loginState = .error(.invalidUrl(error))
      return nil
    }

    let connection: Connection

    func makeConnection(_ token: String?) -> Connection {
      Connection(
        url: baseUrl,
        token: token,
        extraHeaders: extraHeaders,
        identityName: selectedIdentity?.name)
    }

    switch credentialMode {
    case .usernameAndPassword:
      Logger.shared.info("Credential mode is username and password")

      do throws(LoginError) {
        let token = try await fetchToken(url: tokenUrl)
        Logger.shared.info("Username and password are valid, have token")
        connection = makeConnection(token)
      } catch .otpRequired {
        Logger.shared.debug("OTP required, enabling OTP input field")
        otpEnabled = true
        credentialState = .none
        return nil
      } catch {
        credentialState = .error(error)
        return nil
      }

    case .token:
      connection = makeConnection(token)

    case .oidc:
      guard let client = oidcClient, let auth, let provider else {
        Logger.shared.warning(
          "Somehow ended up in validateCredentials with OIDC mode, but no auth and no provider (internal error)"
        )
        credentialState = .none
        return nil
      }

      do {
        let token = try await client.login(provider: provider, auth: auth)
        connection = makeConnection(token)
      } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
        Logger.shared.debug("User canceled login")
        credentialState = .none
        return nil
      } catch {
        Logger.shared.error("Error when executing OIDC flow with provider \(provider.id): \(error)")
        // @TODO: Handle cancel separately as that's not really an error
        //        https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsessionerror/canceledlogin
        credentialState = .error(LoginError(other: error))
        return nil
      }
    case .none:
      connection = makeConnection(nil)
    }

    Logger.shared.debug("Building repository instance with connection for testing")
    let repository = await ApiRepository(
      connection: connection, mode: Bundle.main.appConfiguration.mode)

    Logger.shared.info("Requesting current user")
    let currentUser: User
    do {
      currentUser = try await repository.currentUser()
    } catch let RequestError.forbidden(detail) {
      Logger.shared.error("User logging in does not have permissions to get permissions")
      credentialState = .error(.request(.forbidden(detail: detail)))
      return nil
    } catch RequestError.unauthorized {
      credentialState = .error(.invalidToken)
      return nil
    } catch {
      Logger.shared.error("Error during login with url \(error)")
      credentialState = .error(.init(other: error))
      return nil
    }

    Logger.shared.info("Have user: \(currentUser.username)")

    if currentUser.username != username {
      Logger.api.warning("Username from login and logged in username not the same")
    }

    let stored = StoredConnection(
      url: baseUrl,
      extraHeaders: extraHeaders,
      user: currentUser,
      identity: selectedIdentity?.name)
    if let token = connection.token {
      Logger.api.info("Have token for connection, storing")
      do throws(Keychain.KeychainError) {
        try stored.setToken(token)
      } catch {
        Logger.shared.error(
          "Error during login with url (failed to store token in keychain: \(error)")
        credentialState = .error(.init(other: error))
        return nil
      }
    } else {
      Logger.api.info("No token for connection, leaving nil")
    }

    Logger.api.info("Credentials are valid")

    credentialState = .valid

    return stored
  }
}
