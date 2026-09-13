//
//  TransportFailureRepositoryTest.swift
//  Networking
//
//  End to end through `ApiRepository`: a connectivity failure leaves the
//  repository as `RequestError.connectivity`, classified against the path
//  status sampled when the request failed.
//

import Common
import DataModel
import Foundation
import Testing

@testable import Networking

// Dedicated URLProtocol subclass with its own static responder so this suite
// doesn't race against other suites that share a mock URLProtocol global.
final class TransportFailureMockURLProtocol: URLProtocol, @unchecked Sendable {
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
    config.protocolClasses = [TransportFailureMockURLProtocol.self]
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

// Serialized, and the only suite touching `NetworkPathProbe`: the probe is
// process-wide, so its own tests live here too rather than racing this one.
@MainActor
@Suite(.serialized)
struct TransportFailureRepositoryTest {
  // MARK: - NetworkPathProbe

  @Test
  func probeIsUnknownUntilAMonitorReports() {
    NetworkPathProbe.reset()
    defer { NetworkPathProbe.reset() }

    #expect(NetworkPathProbe.sample() == .unknown)
    NetworkPathProbe.update(interfaceSatisfied: true)
    #expect(NetworkPathProbe.sample() == .satisfied)
    NetworkPathProbe.update(interfaceSatisfied: false)
    #expect(NetworkPathProbe.sample() == .unsatisfied)
  }

  @Test
  func forcedOfflineOverridesAndClearingRestoresTheInterface() {
    NetworkPathProbe.reset()
    defer { NetworkPathProbe.reset() }

    NetworkPathProbe.update(interfaceSatisfied: true)
    NetworkPathProbe.setForcedOffline(true)
    #expect(NetworkPathProbe.sample() == .unsatisfied)

    // Another monitor pushing the real path must not switch the override off.
    NetworkPathProbe.update(interfaceSatisfied: true)
    #expect(NetworkPathProbe.sample() == .unsatisfied)

    NetworkPathProbe.setForcedOffline(false)
    #expect(NetworkPathProbe.sample() == .satisfied)
  }

  @Test
  func forcedOfflineAppliesBeforeTheFirstPath() {
    NetworkPathProbe.reset()
    defer { NetworkPathProbe.reset() }

    NetworkPathProbe.setForcedOffline(true)
    #expect(NetworkPathProbe.sample() == .unsatisfied)
    NetworkPathProbe.setForcedOffline(false)
    #expect(NetworkPathProbe.sample() == .unknown)
  }

  // MARK: - Through ApiRepository

  private static func makeRepo() -> ApiRepository {
    ApiRepository(
      connection: Connection(
        url: URL(string: "https://example.com")!, token: "t", identityName: nil,
        serverID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!),
      mode: .release,
      contentStore: nil,
      urlSession: TransportFailureMockURLProtocol.makeSession())
  }

  private static func failure(
    of operation: () async throws -> Void
  ) async -> (any Error)? {
    do {
      try await operation()
      return nil
    } catch {
      return error
    }
  }

  @Test(.bug("https://github.com/paulgessinger/swift-paperless/issues/667", id: 667))
  func classifiesAgainstThePathAtFailureTime() async throws {
    NetworkPathProbe.reset()
    NetworkPathProbe.update(interfaceSatisfied: true)
    TransportFailureMockURLProtocol.responder = { _ in throw URLError(.cannotConnectToHost) }
    defer {
      NetworkPathProbe.reset()
      TransportFailureMockURLProtocol.reset()
    }

    let repo = Self.makeRepo()

    let online = await Self.failure { _ = try await repo.notes(documentId: 1) }
    guard
      case .connectivity(.cannotConnectToHost, .serverNotResponding, _) = online as? RequestError
    else {
      Issue.record(
        "Expected .connectivity(cannotConnectToHost, serverNotResponding), got \(String(describing: online))"
      )
      return
    }

    // Same repository, same failure; only the path changed before it failed.
    NetworkPathProbe.update(interfaceSatisfied: false)
    let offline = await Self.failure { _ = try await repo.notes(documentId: 1) }
    guard case .connectivity(.cannotConnectToHost, .offline, _) = offline as? RequestError else {
      Issue.record(
        "Expected .connectivity(cannotConnectToHost, offline), got \(String(describing: offline))")
      return
    }
  }

  // One outage across the endpoints the detail view loads together is one
  // error value, so it collapses into one message.
  @Test
  func oneOutageIsOneErrorAcrossEndpoints() async throws {
    NetworkPathProbe.reset()
    NetworkPathProbe.update(interfaceSatisfied: true)
    TransportFailureMockURLProtocol.responder = { _ in throw URLError(.cannotFindHost) }
    defer {
      NetworkPathProbe.reset()
      TransportFailureMockURLProtocol.reset()
    }

    let repo = Self.makeRepo()
    let notes = await Self.failure { _ = try await repo.notes(documentId: 1) }
    let metadata = await Self.failure { _ = try await repo.metadata(documentId: 1) }

    let a = try #require(notes as? RequestError)
    let b = try #require(metadata as? RequestError)
    #expect(a == b)
    guard case .connectivity(.cannotFindHost, .hostNotFound, _) = a else {
      Issue.record("Expected .connectivity(cannotFindHost, hostNotFound), got \(a)")
      return
    }
  }

  // Not connectivity-class: reaches the caller as the raw URLError, as before.
  @Test
  func otherTransportFailuresPassThrough() async throws {
    TransportFailureMockURLProtocol.responder = { _ in throw URLError(.badServerResponse) }
    defer { TransportFailureMockURLProtocol.reset() }

    let repo = Self.makeRepo()
    let error = await Self.failure { _ = try await repo.notes(documentId: 1) }
    #expect((error as? URLError)?.code == .badServerResponse)
  }
}
