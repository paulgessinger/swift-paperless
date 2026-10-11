//
//  ApiRepositoryStaleConnectionRetryTest.swift
//  Networking
//
//  A read whose connection stalls or drops mid-flight is retried once; a
//  write is not, since the server may already have applied it.
//

import Common
import Foundation
import Testing

@testable import Networking

// Own URLProtocol with its own responder, so this suite can't race others.
final class StaleConnectionMockURLProtocol: URLProtocol, @unchecked Sendable {
  typealias Responder = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

  private static let lock = NSLock()
  nonisolated(unsafe) private static var _responder: Responder?

  static var responder: Responder? {
    get { lock.withLock { _responder } }
    set { lock.withLock { _responder = newValue } }
  }

  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StaleConnectionMockURLProtocol.self]
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
struct ApiRepositoryStaleConnectionRetryTest {
  nonisolated static let url = URL(string: "https://example.com/api/documents/")!

  final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func bumpAndGet() -> Int {
      lock.withLock {
        _value += 1
        return _value
      }
    }
  }

  static func makeRepo() -> ApiRepository {
    ApiRepository(
      connection: Connection(
        url: URL(string: "https://example.com")!, token: "t", identityName: nil),
      mode: .release, contentStore: nil, urlSession: StaleConnectionMockURLProtocol.makeSession(),
      apiVersion: 9, backendVersion: Version(2, 18, 0))
  }

  // The first attempt fails with `code`, the second succeeds.
  static func failFirst(with code: URLError.Code, hits: Counter) {
    StaleConnectionMockURLProtocol.responder = { req in
      if hits.bumpAndGet() == 1 { throw URLError(code) }
      return (
        HTTPURLResponse(
          url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
        Data("[\"ok\"]".utf8)
      )
    }
  }

  @Test(arguments: [URLError.Code.timedOut, .networkConnectionLost])
  func readRetriesOnce(code: URLError.Code) async throws {
    let hits = Counter()
    Self.failFirst(with: code, hits: hits)
    defer { StaleConnectionMockURLProtocol.responder = nil }

    let repo = Self.makeRepo()
    let result = try await repo.fetchData(for: repo.request(url: Self.url), as: [String].self)
    #expect(result == ["ok"])
    #expect(hits.value == 2)
  }

  @Test
  func readGivesUpAfterOneRetry() async throws {
    let hits = Counter()
    StaleConnectionMockURLProtocol.responder = { _ in
      _ = hits.bumpAndGet()
      throw URLError(.timedOut)
    }
    defer { StaleConnectionMockURLProtocol.responder = nil }

    let repo = Self.makeRepo()
    await #expect(throws: RequestError.self) {
      _ = try await repo.fetchData(for: repo.request(url: Self.url), as: [String].self)
    }
    #expect(hits.value == 2)
  }

  @Test
  func writeIsNotRetried() async throws {
    let hits = Counter()
    Self.failFirst(with: .timedOut, hits: hits)
    defer { StaleConnectionMockURLProtocol.responder = nil }

    let repo = Self.makeRepo()
    var request = repo.request(url: Self.url)
    request.httpMethod = "POST"
    await #expect(throws: RequestError.self) {
      _ = try await repo.fetchData(for: request, as: [String].self)
    }
    #expect(hits.value == 1)
  }

  @Test
  func otherFailuresAreNotRetried() async throws {
    let hits = Counter()
    Self.failFirst(with: .cannotFindHost, hits: hits)
    defer { StaleConnectionMockURLProtocol.responder = nil }

    let repo = Self.makeRepo()
    await #expect(throws: RequestError.self) {
      _ = try await repo.fetchData(for: repo.request(url: Self.url), as: [String].self)
    }
    #expect(hits.value == 1)
  }
}
