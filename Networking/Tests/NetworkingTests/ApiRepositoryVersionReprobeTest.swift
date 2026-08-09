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
struct ApiRepositoryVersionReprobeTest {
  nonisolated static let baseURL = URL(string: "https://example.com")!
  nonisolated static let serverID = UUID(
    uuidString: "99999999-8888-7777-6666-555555555555")!

  // Atomic counter for request-count assertions across concurrent callbacks.
  final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func bump() { lock.withLock { _value += 1 } }
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
  @Test
  func concurrentUnsupportedVersionShareSingleProbe() async throws {
    let repo = Self.makeRepo(apiVersion: ApiRepository.minimumApiVersion)
    let uiSettingsHits = Counter()
    VersionMockURLProtocol.responder = { req in
      let accept = req.value(forHTTPHeaderField: "Accept") ?? ""
      if (req.url?.path ?? "").contains("ui_settings") {
        uiSettingsHits.bump()
        return (Self.uiSettingsResponse(for: req, apiVersion: "7"), Data("{}".utf8))
      }
      if accept.contains("version=7") {
        return Self.response(for: req, status: 200, body: Data("[\"ok\"]".utf8))
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
