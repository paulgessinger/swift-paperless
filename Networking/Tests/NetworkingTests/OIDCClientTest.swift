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
    let token = try await client.exchangeIdTokenWithPaperless(
      providerId: "authentik",
      clientId: "client-123",
      idToken: "the-id-token",
      csrf: "csrf-value"
    )

    #expect(token == "paperless-api-token")
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
}
