import Common
import Foundation
import Testing

@testable import Networking

@MainActor
@Suite(.serialized)
struct OIDCClientTest {
  private static let baseURL = URL(string: "https://paperless.example.com/")!
  // Matches the production scheme registered in swift-paperless/Info.plist
  // and the redirect URI built in LoginViewModel.makeOIDCClient().
  private static let redirectURI = URL(string: "x-paperless://oidc-callback")!
  private static let tokenEndpoint = URL(string: "https://idp.example.com/application/o/token/")!

  private func makeClient() throws -> OIDCClient {
    try OIDCClient(
      baseURL: Self.baseURL,
      redirectURI: Self.redirectURI,
      session: MockURLProtocol.makeSession()
    )
  }

  private func httpResponse(url: URL, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
  }

  // MARK: - exchangeCode

  @Test func exchangeCode_returnsIdTokenOnSuccess() async throws {
    let body = #"{"id_token":"the-id-token","access_token":"x","token_type":"bearer"}"#
    MockURLProtocol.responder = { [tokenEndpoint = Self.tokenEndpoint] request in
      #expect(request.url == tokenEndpoint)
      #expect(request.httpMethod == "POST")
      return (
        HTTPURLResponse(
          url: tokenEndpoint, statusCode: 200, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"])!,
        Data(body.utf8)
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try makeClient()
    let token = try await client.exchangeCode(
      tokenEndpoint: Self.tokenEndpoint,
      clientId: "client-123",
      code: "auth-code",
      pkce: PKCE()
    )

    #expect(token.id_token == "the-id-token")
  }

  @Test func exchangeCode_surfacesOAuth2ErrorOn4xx() async throws {
    // Authentik's response when an OAuth2 client is configured as "confidential"
    // but the app (a public client) sends no client_secret.
    let body = #"""
      {"error":"invalid_client","error_description":"Client authentication failed (e.g. unknown client, no client authentication included, or unsupported authentication method)"}
      """#
    MockURLProtocol.responder = { [tokenEndpoint = Self.tokenEndpoint] _ in
      (
        HTTPURLResponse(
          url: tokenEndpoint, statusCode: 401, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"])!,
        Data(body.utf8)
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try makeClient()

    await #expect(throws: OIDCError.self) {
      _ = try await client.exchangeCode(
        tokenEndpoint: Self.tokenEndpoint,
        clientId: "client-123",
        code: "auth-code",
        pkce: PKCE()
      )
    }

    // The actual contract we want: a typed OIDC error containing the OAuth2
    // `error` and `error_description` fields so the UI can render something
    // actionable instead of `the data couldn't be read because it's missing`.
    do {
      _ = try await client.exchangeCode(
        tokenEndpoint: Self.tokenEndpoint,
        clientId: "client-123",
        code: "auth-code",
        pkce: PKCE()
      )
      Issue.record("expected exchangeCode to throw")
    } catch let error as OIDCError {
      guard case .tokenExchangeFailed(let oauthError, let description) = error else {
        Issue.record("expected OIDCError.tokenExchangeFailed, got \(error)")
        return
      }
      #expect(oauthError == "invalid_client")
      #expect(description?.contains("Client authentication failed") == true)
    } catch {
      Issue.record("expected OIDCError, got \(type(of: error)): \(error)")
    }
  }

  @Test func exchangeCode_surfacesOAuth2ErrorWithoutDescription() async throws {
    let body = #"{"error":"invalid_grant"}"#
    MockURLProtocol.responder = { [tokenEndpoint = Self.tokenEndpoint] _ in
      (
        HTTPURLResponse(
          url: tokenEndpoint, statusCode: 400, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"])!,
        Data(body.utf8)
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try makeClient()

    do {
      _ = try await client.exchangeCode(
        tokenEndpoint: Self.tokenEndpoint,
        clientId: "client-123",
        code: "auth-code",
        pkce: PKCE()
      )
      Issue.record("expected exchangeCode to throw")
    } catch let error as OIDCError {
      guard case .tokenExchangeFailed(let oauthError, let description) = error else {
        Issue.record("expected OIDCError.tokenExchangeFailed, got \(error)")
        return
      }
      #expect(oauthError == "invalid_grant")
      #expect(description == nil)
    } catch {
      Issue.record("expected OIDCError, got \(type(of: error)): \(error)")
    }
  }

  // MARK: - fetchScope

  // Regression for #559: Django's CSRF middleware rejects HTTPS POSTs that carry
  // neither `Origin` nor `Referer` (it falls back to strict referer checking for
  // secure requests), returning 403 even though the CSRF token is valid. The app
  // must set a `Referer` header so the same-origin check passes.
  @Test(.bug("https://github.com/paulgessinger/swift-paperless/issues/559", id: 559))
  func fetchScope_setsRefererHeader() async throws {
    let redirectURL = Self.baseURL.appendingPathComponent(
      "api/auth/headless/browser/v1/auth/provider/redirect")
    MockURLProtocol.responder = { [baseURL = Self.baseURL] request in
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Referer") == baseURL.absoluteString)
      return (
        HTTPURLResponse(
          url: redirectURL, statusCode: 302, httpVersion: "HTTP/1.1",
          headerFields: ["Location": "https://idp.example.com/authorize?scope=openid"])!,
        Data()
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try makeClient()
    let scope = try await client.fetchScope(providerId: "authentik", csrf: "csrf-value")

    #expect(scope == "openid")
  }

  // MARK: - exchangeIdTokenWithPaperless

  @Test func exchangeIdTokenWithPaperless_returnsTokenOnSuccess() async throws {
    let body = #"""
      {"meta":{"access_token":"paperless-api-token"},"status":200}
      """#
    let expectedURL = Self.baseURL.appendingPathComponent(
      "api/auth/headless/app/v1/auth/provider/token")
    MockURLProtocol.responder = { request in
      #expect(request.url == expectedURL)
      return (
        HTTPURLResponse(
          url: expectedURL, statusCode: 200, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"])!,
        Data(body.utf8)
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try makeClient()
    let result = try await client.exchangeIdTokenWithPaperless(
      providerId: "authentik",
      clientId: "client-123",
      idToken: "the-id-token",
      csrf: "csrf-value"
    )

    #expect(result == .success(token: "paperless-api-token"))
  }

  // Regression for #559: this POST hits the same Django CSRF middleware as
  // fetchScope, so it must also carry a `Referer` header.
  @Test(.bug("https://github.com/paulgessinger/swift-paperless/issues/559", id: 559))
  func exchangeIdTokenWithPaperless_setsRefererHeader() async throws {
    let body = #"{"meta":{"access_token":"paperless-api-token"},"status":200}"#
    let expectedURL = Self.baseURL.appendingPathComponent(
      "api/auth/headless/app/v1/auth/provider/token")
    MockURLProtocol.responder = { [baseURL = Self.baseURL] request in
      #expect(request.value(forHTTPHeaderField: "Referer") == baseURL.absoluteString)
      return (
        HTTPURLResponse(
          url: expectedURL, statusCode: 200, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"])!,
        Data(body.utf8)
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try makeClient()
    _ = try await client.exchangeIdTokenWithPaperless(
      providerId: "authentik",
      clientId: "client-123",
      idToken: "the-id-token",
      csrf: "csrf-value"
    )
  }

  @Test func exchangeIdTokenWithPaperless_surfacesErrorBodyOn4xx() async throws {
    let body = #"""
      {"status":400,"errors":[{"message":"Invalid id_token","code":"invalid"}]}
      """#
    let expectedURL = Self.baseURL.appendingPathComponent(
      "api/auth/headless/app/v1/auth/provider/token")
    MockURLProtocol.responder = { _ in
      (
        HTTPURLResponse(
          url: expectedURL, statusCode: 400, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"])!,
        Data(body.utf8)
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try makeClient()

    do {
      _ = try await client.exchangeIdTokenWithPaperless(
        providerId: "authentik",
        clientId: "client-123",
        idToken: "the-id-token",
        csrf: "csrf-value"
      )
      Issue.record("expected exchangeIdTokenWithPaperless to throw")
    } catch let error as OIDCError {
      guard case .paperlessTokenExchangeFailed(let statusCode, let raw) = error else {
        Issue.record("expected OIDCError.paperlessTokenExchangeFailed, got \(error)")
        return
      }
      #expect(statusCode == 400)
      #expect(raw.contains("Invalid id_token"))
    } catch {
      Issue.record("expected OIDCError, got \(type(of: error)): \(error)")
    }
  }

  // MARK: - exchangeIdTokenWithPaperless (MFA)

  @Test func exchangeIdTokenWithPaperless_returnsMfaRequiredOnPendingMfa() async throws {
    // allauth headless returns 401 with a pending `mfa_authenticate` flow and
    // a session token when a second factor (TOTP) is required to finish the
    // login.
    let body = #"""
      {"status":401,"data":{"flows":[{"id":"login"},{"id":"mfa_authenticate","is_pending":true,"types":["totp"]}]},"meta":{"is_authenticated":false,"session_token":"pending-session-token"}}
      """#
    let expectedURL = Self.baseURL.appendingPathComponent(
      "api/auth/headless/app/v1/auth/provider/token")
    MockURLProtocol.responder = { _ in
      (
        HTTPURLResponse(
          url: expectedURL, statusCode: 401, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"])!,
        Data(body.utf8)
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try makeClient()
    let result = try await client.exchangeIdTokenWithPaperless(
      providerId: "authentik",
      clientId: "client-123",
      idToken: "the-id-token",
      csrf: "csrf-value"
    )

    #expect(result == .mfaRequired(sessionToken: "pending-session-token"))
  }

  @Test func exchangeIdTokenWithPaperless_throwsOn401WithoutMfaFlow() async throws {
    // A 401 that is not a pending MFA stage (e.g. a genuinely rejected token)
    // must keep surfacing as a regular token exchange failure.
    let body = #"""
      {"status":401,"data":{"flows":[{"id":"login"}]},"meta":{"is_authenticated":false}}
      """#
    let expectedURL = Self.baseURL.appendingPathComponent(
      "api/auth/headless/app/v1/auth/provider/token")
    MockURLProtocol.responder = { _ in
      (
        HTTPURLResponse(
          url: expectedURL, statusCode: 401, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"])!,
        Data(body.utf8)
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try makeClient()

    do {
      _ = try await client.exchangeIdTokenWithPaperless(
        providerId: "authentik",
        clientId: "client-123",
        idToken: "the-id-token",
        csrf: "csrf-value"
      )
      Issue.record("expected exchangeIdTokenWithPaperless to throw")
    } catch let error as OIDCError {
      guard case .paperlessTokenExchangeFailed(let statusCode, _) = error else {
        Issue.record("expected OIDCError.paperlessTokenExchangeFailed, got \(error)")
        return
      }
      #expect(statusCode == 401)
    } catch {
      Issue.record("expected OIDCError, got \(type(of: error)): \(error)")
    }
  }

  // MARK: - confirmMFA

  @Test func confirmMFA_returnsTokenOnSuccess() async throws {
    let body = #"""
      {"status":200,"data":{"user":{"id":1}},"meta":{"is_authenticated":true,"access_token":"paperless-api-token"}}
      """#
    let expectedURL = Self.baseURL.appendingPathComponent(
      "api/auth/headless/app/v1/auth/2fa/authenticate")
    MockURLProtocol.responder = { request in
      #expect(request.url == expectedURL)
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "x-session-token") == "pending-session-token")
      // URLProtocol observes the body through httpBodyStream; read it back so
      // the responder can inspect the JSON payload.
      var bodyData = request.httpBody
      if bodyData == nil, let stream = request.httpBodyStream {
        stream.open()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var read = stream.read(&buffer, maxLength: buffer.count)
        while read > 0 {
          bodyData = (bodyData ?? Data()) + Data(buffer.prefix(read))
          read = stream.read(&buffer, maxLength: buffer.count)
        }
      }
      if let bodyData,
        let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String]
      {
        #expect(body["code"] == "123456")
      } else {
        Issue.record("confirmMFA request did not carry a JSON code body")
      }
      return (
        HTTPURLResponse(
          url: expectedURL, statusCode: 200, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"])!,
        Data(body.utf8)
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try makeClient()
    client.pendingMFASessionToken = "pending-session-token"

    let token = try await client.confirmMFA(code: "123456")

    #expect(token == "paperless-api-token")
  }

  @Test func confirmMFA_surfacesIncorrectCodeOn400() async throws {
    let body = #"""
      {"status":400,"errors":[{"code":"incorrect_code","param":"code","message":"The entered code is not valid."}]}
      """#
    let expectedURL = Self.baseURL.appendingPathComponent(
      "api/auth/headless/app/v1/auth/2fa/authenticate")
    MockURLProtocol.responder = { _ in
      (
        HTTPURLResponse(
          url: expectedURL, statusCode: 400, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"])!,
        Data(body.utf8)
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try makeClient()
    client.pendingMFASessionToken = "pending-session-token"

    do {
      _ = try await client.confirmMFA(code: "000000")
      Issue.record("expected confirmMFA to throw")
    } catch let error as OIDCError {
      guard case .invalidCode = error else {
        Issue.record("expected OIDCError.invalidCode, got \(error)")
        return
      }
    } catch {
      Issue.record("expected OIDCError, got \(type(of: error)): \(error)")
    }
  }

  @Test func confirmMFA_surfacesSessionExpiredOn401() async throws {
    let expectedURL = Self.baseURL.appendingPathComponent(
      "api/auth/headless/app/v1/auth/2fa/authenticate")
    MockURLProtocol.responder = { _ in
      (
        HTTPURLResponse(
          url: expectedURL, statusCode: 401, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"])!,
        Data()
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try makeClient()
    client.pendingMFASessionToken = "pending-session-token"

    do {
      _ = try await client.confirmMFA(code: "123456")
      Issue.record("expected confirmMFA to throw")
    } catch let error as OIDCError {
      guard case .mfaSessionExpired = error else {
        Issue.record("expected OIDCError.mfaSessionExpired, got \(error)")
        return
      }
    } catch {
      Issue.record("expected OIDCError, got \(type(of: error)): \(error)")
    }
  }

  @Test func confirmMFA_throwsWithoutPendingSession() async {
    let url = URL(string: "https://example.com")!
    MockURLProtocol.responder = { _ in
      (
        HTTPURLResponse(
          url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
        Data()
      )
    }
    defer { MockURLProtocol.reset() }

    let client = try! makeClient()

    do {
      _ = try await client.confirmMFA(code: "123456")
      Issue.record("expected confirmMFA to throw")
    } catch let error as OIDCError {
      guard case .mfaSessionMissing = error else {
        Issue.record("expected OIDCError.mfaSessionMissing, got \(error)")
        return
      }
    } catch {
      Issue.record("expected OIDCError, got \(type(of: error)): \(error)")
    }
  }
}
