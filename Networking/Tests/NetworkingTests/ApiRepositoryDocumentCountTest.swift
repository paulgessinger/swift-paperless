//
//  ApiRepositoryDocumentCountTest.swift
//  Networking
//
//  Exercises the cheap document-count probe used to pick a size-adaptive
//  default for OfflineBrowsingMode right after login.
//

import Common
import DataModel
import Foundation
import Testing

@testable import Networking

// Dedicated URLProtocol subclass with its own static responder so this suite
// doesn't race against other suites that share a mock URLProtocol global.
final class DocumentCountMockURLProtocol: URLProtocol, @unchecked Sendable {
  typealias Responder = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

  private static let lock = NSLock()
  nonisolated(unsafe) private static var _responder: Responder?

  static var responder: Responder? {
    get { lock.withLock { _responder } }
    set { lock.withLock { _responder = newValue } }
  }

  static func reset() { responder = nil }

  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DocumentCountMockURLProtocol.self]
    return URLSession(configuration: config)
  }

  override class func canInit(with _: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let responder = Self.responder else {
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      return
    }
    do {
      let (response, data) = try responder(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct ApiRepositoryDocumentCountTest {
  nonisolated static let baseURL = URL(string: "https://example.com")!
  nonisolated static let serverID = UUID(
    uuidString: "11111111-2222-3333-4444-555555555555")!

  static func makeRepo() -> ApiRepository {
    ApiRepository(
      connection: Connection(
        url: baseURL, token: "t", identityName: nil, serverID: serverID),
      mode: .release,
      contentStore: nil,
      urlSession: DocumentCountMockURLProtocol.makeSession())
  }

  nonisolated static let oneDocumentJSON = """
    {
      "id": 2724,
      "title": "Quittung",
      "content": "bla bla bla",
      "tags": [],
      "created": "2024-12-21T00:00:00+01:00",
      "user_can_change": true,
      "permissions": {
        "view": { "users": [], "groups": [] },
        "change": { "users": [], "groups": [] }
      },
      "custom_fields": []
    }
    """

  @Test
  func returnsCountFromEnvelope() async throws {
    DocumentCountMockURLProtocol.responder = { req in
      #expect(req.url?.query?.contains("page=1") == true)
      #expect(req.url?.query?.contains("page_size=1") == true)
      let body = """
        { "count": 12345, "next": null, "previous": null, "results": [\(Self.oneDocumentJSON)] }
        """
      return (
        HTTPURLResponse(
          url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
        Data(body.utf8)
      )
    }
    defer { DocumentCountMockURLProtocol.reset() }

    let repo = Self.makeRepo()
    let count = try await repo.documentCount()
    #expect(count == 12345)
  }

  @Test
  func propagatesNetworkError() async throws {
    DocumentCountMockURLProtocol.responder = { _ in
      throw URLError(.cannotConnectToHost)
    }
    defer { DocumentCountMockURLProtocol.reset() }

    let repo = Self.makeRepo()
    await #expect(throws: Error.self) {
      _ = try await repo.documentCount()
    }
  }
}
