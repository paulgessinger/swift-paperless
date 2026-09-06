//
//  ApiRepositoryVersionReprobeTest.swift
//  Networking
//
//  Exercises the runtime API-version re-probe: when a request is rejected with
//  406 (`unsupportedVersion`) — e.g. the version was locked in against an
//  unreachable backend — the repository re-detects the version and retries the
//  request once with a corrected Accept header.
//

import Common
import DataModel
import Foundation
import Testing

@testable import Networking

// Dedicated URLProtocol subclass with its own static responder so this suite
// doesn't race against other suites that share a mock URLProtocol global.
final class VersionMockURLProtocol: URLProtocol, @unchecked Sendable {
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
    config.protocolClasses = [VersionMockURLProtocol.self]
    return URLSession(configuration: config)
  }

  override class func canInit(with _: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  // Responders in this suite park on gates to pin down request ordering, so
  // each load runs on its own global-queue thread: a blocked responder must not
  // hold up the other requests the same test has in flight.
  override func startLoading() {
    DispatchQueue.global().async { [self] in
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
  }

  override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct ApiRepositoryVersionReprobeTest {
  nonisolated static let baseURL = URL(string: "https://example.com")!
  nonisolated static let serverID = UUID(
    uuidString: "99999999-8888-7777-6666-555555555555")!

  // Atomic counter for request-count assertions across concurrent callbacks.
  // Doubles as a gate: `wait(untilAtLeast:)` lets one mock responder block
  // until another has run, which is how these tests pin the interleaving
  // instead of hoping for one.
  final class Counter: @unchecked Sendable {
    private let condition = NSCondition()
    private var _value = 0

    var value: Int {
      condition.lock()
      defer { condition.unlock() }
      return _value
    }

    func bump() {
      _ = bumpAndGet()
    }

    @discardableResult
    func bumpAndGet() -> Int {
      condition.lock()
      defer { condition.unlock() }
      _value += 1
      condition.broadcast()
      return _value
    }

    // Blocks until the counter reaches `target`. Returns false on timeout, so a
    // test whose expected ordering never materialises fails instead of hanging.
    @discardableResult
    func wait(untilAtLeast target: Int, timeout: TimeInterval = 20) -> Bool {
      condition.lock()
      defer { condition.unlock() }
      let deadline = Date().addingTimeInterval(timeout)
      while _value < target {
        if !condition.wait(until: deadline) { return false }
      }
      return true
    }
  }

  static func makeRepo(apiVersion: UInt?, backendVersion: Version? = nil) -> ApiRepository {
    ApiRepository(
      connection: Connection(
        url: baseURL, token: "t", identityName: nil, serverID: serverID),
      mode: .release,
      contentStore: nil,
      urlSession: VersionMockURLProtocol.makeSession(),
      apiVersion: apiVersion,
      backendVersion: backendVersion)
  }

  nonisolated static func dataURL() -> URL {
    baseURL.appendingPathComponent("api/documents/")
  }

  nonisolated static func uiSettingsResponse(
    for request: URLRequest, apiVersion: String, backendVersion: String = "2.14.0"
  ) -> HTTPURLResponse {
    HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: [
        "X-Api-Version": apiVersion,
        "X-Version": backendVersion,
      ])!
  }

  nonisolated static func response(
    for request: URLRequest, status: Int, body: Data = Data()
  ) -> (HTTPURLResponse, Data) {
    (
      HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: nil)!,
      body
    )
  }

  // The backend was unreachable at init (version locked in at the minimum). A
  // request 406s; the re-probe learns the real version and the retry succeeds.
  @Test
  func reprobesAndRetriesOnUnsupportedVersion() async throws {
    let repo = Self.makeRepo(apiVersion: ApiRepository.minimumApiVersion)
    let uiSettingsHits = Counter()
    VersionMockURLProtocol.responder = { req in
      let accept = req.value(forHTTPHeaderField: "Accept") ?? ""
      if (req.url?.path ?? "").contains("ui_settings") {
        uiSettingsHits.bump()
        return (Self.uiSettingsResponse(for: req, apiVersion: "7"), Data("{}".utf8))
      }
      // Data endpoint: reject the locked-in minimum, accept the re-probed version.
      if accept.contains("version=7") {
        return Self.response(for: req, status: 200, body: Data("[\"ok\"]".utf8))
      }
      return Self.response(for: req, status: 406)
    }
    defer { VersionMockURLProtocol.reset() }

    let request = repo.request(url: Self.dataURL())
    let result = try await repo.fetchData(for: request, as: [String].self)

    #expect(result == ["ok"])
    #expect(repo.effectiveApiVersion == 7)
    #expect(uiSettingsHits.value == 1)
  }

  // Several requests 406 at once (backend just came back online): they must
  // share a single re-probe rather than each running the version sweep.
  //
  // The ordering is forced rather than raced: the probe response is held until
  // both requests have been rejected, so the second caller provably reaches the
  // re-probe path while the first probe is still in flight.
  @Test
  func concurrentUnsupportedVersionShareSingleProbe() async throws {
    let repo = Self.makeRepo(apiVersion: ApiRepository.minimumApiVersion)
    let uiSettingsHits = Counter()
    let rejections = Counter()
    let orderingHeld = Counter()
    VersionMockURLProtocol.responder = { req in
      let accept = req.value(forHTTPHeaderField: "Accept") ?? ""
      if (req.url?.path ?? "").contains("ui_settings") {
        // Hold the probe open until both requests have been 406'd.
        if rejections.wait(untilAtLeast: 2) { orderingHeld.bump() }
        uiSettingsHits.bump()
        return (Self.uiSettingsResponse(for: req, apiVersion: "7"), Data("{}".utf8))
      }
      if accept.contains("version=7") {
        return Self.response(for: req, status: 200, body: Data("[\"ok\"]".utf8))
      }
      rejections.bump()
      return Self.response(for: req, status: 406)
    }
    defer { VersionMockURLProtocol.reset() }

    let request = repo.request(url: Self.dataURL())
    async let a = repo.fetchData(for: request, as: [String].self)
    async let b = repo.fetchData(for: request, as: [String].self)
    let results = try await [a, b]

    #expect(results[0] == ["ok"])
    #expect(results[1] == ["ok"])
    #expect(repo.effectiveApiVersion == 7)
    #expect(uiSettingsHits.value == 1)
    // Guards the guard: if the gate had timed out, the assertion above would be
    // about timing again rather than about coalescing.
    #expect(orderingHeld.value == 1)
  }

  // The other half of the concurrent case, and the one that used to make
  // `concurrentUnsupportedVersionShareSingleProbe` flaky: the second request's
  // 406 lands *after* the first request's re-probe has already finished and
  // bumped the effective version. Its rejection is stale news — it was sent
  // with the old version — so it must retry with the current version instead of
  // starting a second probe.
  @Test
  func unsupportedVersionForStaleVersionRetriesWithoutReprobing() async throws {
    let repo = Self.makeRepo(apiVersion: ApiRepository.minimumApiVersion)
    let uiSettingsHits = Counter()
    let staleRequests = Counter()
    let acceptedRequests = Counter()
    let orderingHeld = Counter()
    VersionMockURLProtocol.responder = { req in
      let accept = req.value(forHTTPHeaderField: "Accept") ?? ""
      if (req.url?.path ?? "").contains("ui_settings") {
        uiSettingsHits.bump()
        return (Self.uiSettingsResponse(for: req, apiVersion: "7"), Data("{}".utf8))
      }
      if accept.contains("version=7") {
        let response = Self.response(for: req, status: 200, body: Data("[\"ok\"]".utf8))
        acceptedRequests.bump()
        return response
      }
      // Second request sent with the stale version: hold its rejection until
      // the first caller has probed *and* completed its retry, i.e. until the
      // repository definitely holds version 7 and no probe is in flight.
      if staleRequests.bumpAndGet() >= 2 {
        if acceptedRequests.wait(untilAtLeast: 1) { orderingHeld.bump() }
      }
      return Self.response(for: req, status: 406)
    }
    defer { VersionMockURLProtocol.reset() }

    let request = repo.request(url: Self.dataURL())
    async let a = repo.fetchData(for: request, as: [String].self)
    async let b = repo.fetchData(for: request, as: [String].self)
    let results = try await [a, b]

    #expect(results[0] == ["ok"])
    #expect(results[1] == ["ok"])
    #expect(repo.effectiveApiVersion == 7)
    #expect(uiSettingsHits.value == 1)
    #expect(orderingHeld.value == 1)
  }

  // The backend is still unreachable: re-probe can't find a working version, so
  // the original unsupportedVersion error propagates and the version is unchanged.
  @Test
  func propagatesWhenReprobeFails() async throws {
    let repo = Self.makeRepo(apiVersion: ApiRepository.minimumApiVersion)
    VersionMockURLProtocol.responder = { req in
      if (req.url?.path ?? "").contains("ui_settings") {
        throw URLError(.cannotConnectToHost)
      }
      return Self.response(for: req, status: 406)
    }
    defer { VersionMockURLProtocol.reset() }

    let request = repo.request(url: Self.dataURL())
    await #expect(throws: RequestError.self) {
      _ = try await repo.fetchData(for: request, as: [String].self)
    }
    #expect(repo.effectiveApiVersion == ApiRepository.minimumApiVersion)
  }

  // Re-probe returns the same version we already sent: don't retry (it would
  // just 406 again) — propagate the error instead of looping.
  @Test
  func propagatesWhenReprobeYieldsSameVersion() async throws {
    let repo = Self.makeRepo(apiVersion: ApiRepository.minimumApiVersion)
    let uiSettingsHits = Counter()
    VersionMockURLProtocol.responder = { req in
      if (req.url?.path ?? "").contains("ui_settings") {
        uiSettingsHits.bump()
        return (
          Self.uiSettingsResponse(
            for: req, apiVersion: String(ApiRepository.minimumApiVersion)),
          Data("{}".utf8)
        )
      }
      return Self.response(for: req, status: 406)
    }
    defer { VersionMockURLProtocol.reset() }

    let request = repo.request(url: Self.dataURL())
    await #expect(throws: RequestError.self) {
      _ = try await repo.fetchData(for: request, as: [String].self)
    }
    #expect(uiSettingsHits.value == 1)
    #expect(repo.effectiveApiVersion == ApiRepository.minimumApiVersion)
  }
}
