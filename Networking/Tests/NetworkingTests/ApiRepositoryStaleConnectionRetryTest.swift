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
import os

@testable import Networking

// Own URLProtocol with its own responder, so this suite can't race others.
final class StaleConnectionMockURLProtocol: URLProtocol, @unchecked Sendable {
  typealias Responder = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

  /// Thrown by a responder to leave the request unanswered, as a stranded
  /// connection does.
  struct NoAnswer: Error {}

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
    } catch is NoAnswer {
      return
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

  static func makeRepo(epoch: ConnectionEpoch = ConnectionEpoch()) -> ApiRepository {
    ApiRepository(
      connection: Connection(
        url: URL(string: "https://example.com")!, token: "t", identityName: nil),
      mode: .release, contentStore: nil, urlSession: StaleConnectionMockURLProtocol.makeSession(),
      apiVersion: 9, backendVersion: Version(2, 18, 0), connectionEpoch: epoch)
  }

  nonisolated static func ok(_ request: URLRequest) -> (HTTPURLResponse, Data) {
    (
      HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
      Data("[\"ok\"]".utf8)
    )
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

  @Test("A read stranded by a new connection epoch restarts without waiting for its timeout")
  func strandedReadRestarts() async throws {
    let hits = Counter()
    let epoch = ConnectionEpoch()
    StaleConnectionMockURLProtocol.responder = { req in
      guard hits.bumpAndGet() == 1 else { return Self.ok(req) }
      epoch.invalidate()
      throw StaleConnectionMockURLProtocol.NoAnswer()
    }
    defer { StaleConnectionMockURLProtocol.responder = nil }

    let repo = Self.makeRepo(epoch: epoch)
    let result = try await repo.fetchData(for: repo.request(url: Self.url), as: [String].self)
    #expect(result == ["ok"])
    #expect(hits.value == 2)
  }

  @Test(
    "Failing to reach the host retries only if the connection epoch moved",
    arguments: [URLError.Code.cannotFindHost, .dnsLookupFailed, .cannotConnectToHost])
  func unreachableHostRetriesAfterEpochChange(code: URLError.Code) async throws {
    let hits = Counter()
    let epoch = ConnectionEpoch()
    StaleConnectionMockURLProtocol.responder = { req in
      guard hits.bumpAndGet() == 1 else { return Self.ok(req) }
      epoch.invalidate()
      throw URLError(code)
    }
    defer { StaleConnectionMockURLProtocol.responder = nil }

    let repo = Self.makeRepo(epoch: epoch)
    let result = try await repo.fetchData(for: repo.request(url: Self.url), as: [String].self)
    #expect(result == ["ok"])
    #expect(hits.value == 2)
  }

  @Test
  func writeIsNotRetriedAfterEpochChange() async throws {
    let hits = Counter()
    let epoch = ConnectionEpoch()
    StaleConnectionMockURLProtocol.responder = { _ in
      _ = hits.bumpAndGet()
      epoch.invalidate()
      throw URLError(.cannotConnectToHost)
    }
    defer { StaleConnectionMockURLProtocol.responder = nil }

    let repo = Self.makeRepo(epoch: epoch)
    var request = repo.request(url: Self.url)
    request.httpMethod = "POST"
    await #expect(throws: RequestError.self) {
      _ = try await repo.fetchData(for: request, as: [String].self)
    }
    #expect(hits.value == 1)
  }

  @Test("Only a read's first attempt gets the short timeout")
  func retryKeepsFullTimeout() async throws {
    let hits = Counter()
    let timeouts = OSAllocatedUnfairLock(initialState: [TimeInterval]())
    StaleConnectionMockURLProtocol.responder = { req in
      timeouts.withLock { $0.append(req.timeoutInterval) }
      if hits.bumpAndGet() == 1 { throw URLError(.timedOut) }
      return Self.ok(req)
    }
    defer { StaleConnectionMockURLProtocol.responder = nil }

    let repo = Self.makeRepo()
    let request = repo.request(url: Self.url)
    _ = try await repo.fetchData(for: request, as: [String].self)
    #expect(
      timeouts.withLock { $0 } == [ApiRepository.firstReadTimeout, request.timeoutInterval])
    #expect(ApiRepository.firstReadTimeout < request.timeoutInterval)
  }

  @Test("A read with a progress reader keeps its timeout and isn't restarted")
  func fileReadIsLeftAlone() async throws {
    let hits = Counter()
    let timeouts = OSAllocatedUnfairLock(initialState: [TimeInterval]())
    let epoch = ConnectionEpoch()
    StaleConnectionMockURLProtocol.responder = { req in
      timeouts.withLock { $0.append(req.timeoutInterval) }
      _ = hits.bumpAndGet()
      epoch.invalidate()
      return Self.ok(req)
    }
    defer { StaleConnectionMockURLProtocol.responder = nil }

    let repo = Self.makeRepo(epoch: epoch)
    let request = repo.request(url: Self.url)
    _ = try await repo.fetchData(for: request, progress: { _ in })
    #expect(hits.value == 1)
    #expect(timeouts.withLock { $0 } == [request.timeoutInterval])
  }
}

@Suite
struct ConnectionEpochTest {
  @Test("The first route is a baseline, and only a different route advances the epoch")
  func routeChanges() {
    let epoch = ConnectionEpoch()
    epoch.update(route: ["en0"])
    #expect(epoch.value == 0)
    epoch.update(route: ["en0"])
    #expect(epoch.value == 0)
    epoch.update(route: ["utun4", "en0"])
    #expect(epoch.value == 1)
  }

  @Test
  func invalidateAdvances() {
    let epoch = ConnectionEpoch()
    epoch.invalidate()
    #expect(epoch.value == 1)
  }

  @Test("A cancelled caller sees a cancellation, not an epoch change")
  func cancelledCaller() async {
    let epoch = ConnectionEpoch()
    let task = Task {
      try await epoch.cancellingOnChange(from: 0) {
        try await Task.sleep(for: .seconds(60))
      }
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
