//
//  RequestErrorNormalizationTest.swift
//  Networking
//
//  Transport failures thrown by URLSession are normalized into `RequestError` at
//  the repository boundary. The point is that a single outage produces one error
//  *value*, no matter how many endpoints it hit: callers that fan out (the
//  document detail view loads document/metadata/notes/suggestions together)
//  collapse the failures and surface one message instead of four.
//

import Common
import Foundation
import Testing

@testable import Networking

// Dedicated URLProtocol subclass with its own static responder so this suite
// doesn't race against other suites that share a mock URLProtocol global.
final class NormalizationMockURLProtocol: URLProtocol, @unchecked Sendable {
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
    config.protocolClasses = [NormalizationMockURLProtocol.self]
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
struct RequestErrorNormalizationTest {
  private static func urlError(code: Int, failingURL: String) -> NSError {
    NSError(
      domain: NSURLErrorDomain, code: code,
      userInfo: [
        NSLocalizedDescriptionKey: "Could not connect to the server.",
        NSURLErrorFailingURLStringErrorKey: failingURL,
      ])
  }

  // The invariant the whole normalization exists for: the same outage against
  // two different endpoints yields one equal error value.
  @Test
  func sameOutageOnDifferentEndpointsIsOneError() throws {
    let metadata = Self.urlError(
      code: NSURLErrorCannotConnectToHost,
      failingURL: "https://example.com/api/documents/1/metadata/")
    let notes = Self.urlError(
      code: NSURLErrorCannotConnectToHost,
      failingURL: "https://example.com/api/documents/1/notes/")

    // The raw errors are *not* equal — their userInfo carries the failing URL.
    // That is exactly why deduplicating on the raw error (or its description)
    // cannot work, and why we normalize.
    #expect(metadata != notes)

    let a = try #require(RequestError(from: metadata))
    let b = try #require(RequestError(from: notes))

    #expect(a == b)
    #expect(String(describing: a) == String(describing: b))
  }

  @Test
  func preservesTheUnderlyingCode() throws {
    let error = try #require(
      RequestError(
        from: Self.urlError(
          code: NSURLErrorNotConnectedToInternet, failingURL: "https://example.com")))

    // The code survives the conversion: `ErrorSuppression` still needs to tell
    // "device offline" apart from "this server is unreachable".
    guard case .connectivity(let code, let detail) = error else {
      Issue.record("Expected .connectivity, got \(error)")
      return
    }
    #expect(code == .notConnectedToInternet)
    #expect(detail == "Could not connect to the server.")
  }

  @Test
  func mapsSSLFailuresToCertificate() throws {
    let error = try #require(
      RequestError(
        from: Self.urlError(
          code: NSURLErrorServerCertificateUntrusted, failingURL: "https://example.com")))

    guard case .certificate = error else {
      Issue.record("Expected .certificate, got \(error)")
      return
    }
  }

  // Cancellation must never be reinterpreted as a connectivity failure — callers
  // check for it separately and it must never reach the user as an error.
  @Test
  func doesNotConvertCancellation() {
    #expect(
      RequestError(
        from: Self.urlError(code: NSURLErrorCancelled, failingURL: "https://example.com")) == nil)
  }

  // File-I/O codes are about the local filesystem during a download, not
  // reachability, so they are left alone.
  @Test
  func doesNotConvertFileIOErrors() {
    #expect(
      RequestError(
        from: Self.urlError(code: -3003, failingURL: "https://example.com")) == nil)
  }

  @Test
  func doesNotConvertForeignDomains() {
    let error = NSError(domain: "com.example.other", code: -1004)
    #expect(RequestError(from: error) == nil)
  }

  @Test
  func normalizingPassesThroughUnrelatedErrors() {
    struct Custom: Error, Equatable {}
    let result = RequestError.normalizing(Custom())
    #expect(result as? Custom == Custom())
  }

  // End-to-end through the repository: an unreachable server makes the three
  // enrichment endpoints the detail view loads fail with one identical error.
  @Test
  func repositoryCollapsesAnOutageAcrossEndpoints() async throws {
    NormalizationMockURLProtocol.responder = { _ in throw URLError(.cannotConnectToHost) }
    defer { NormalizationMockURLProtocol.reset() }

    let repo = ApiRepository(
      connection: Connection(
        url: URL(string: "https://example.com")!, token: "t", identityName: nil,
        serverID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!),
      mode: .release,
      contentStore: nil,
      urlSession: NormalizationMockURLProtocol.makeSession())

    var thrown: [RequestError] = []
    for endpoint in ["metadata", "notes", "suggestions"] {
      do {
        switch endpoint {
        case "metadata": _ = try await repo.metadata(documentId: 1)
        case "notes": _ = try await repo.notes(documentId: 1)
        default: _ = try await repo.suggestions(documentId: 1)
        }
        Issue.record("Expected \(endpoint) to throw")
      } catch let error as RequestError {
        thrown.append(error)
      }
    }

    #expect(thrown.count == 3)
    for error in thrown {
      guard case .connectivity(let code, _) = error else {
        Issue.record("Expected .connectivity, got \(error)")
        continue
      }
      #expect(code == .cannotConnectToHost)
    }

    // One distinct value across all three → one toast, not three.
    #expect(Set(thrown.map { String(describing: $0) }).count == 1)
  }
}
