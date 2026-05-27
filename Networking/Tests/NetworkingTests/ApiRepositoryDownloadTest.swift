//
//  ApiRepositoryDownloadTest.swift
//  Networking
//

import Common
import DataModel
import Foundation
import Testing

@testable import Networking

// Dedicated URLProtocol subclass with its own static responder, so this
// suite doesn't race against other suites (e.g. OIDCClientTest) that also
// use a mock URLProtocol global.
final class DownloadMockURLProtocol: URLProtocol, @unchecked Sendable {
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
    config.protocolClasses = [DownloadMockURLProtocol.self]
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
struct ApiRepositoryDownloadTest {
  nonisolated static let baseURL = URL(string: "https://example.com")!
  nonisolated static let serverID = UUID(
    uuidString: "11111111-2222-3333-4444-555555555555")!

  static func makeRepo(contentStore: ContentStore) -> ApiRepository {
    let session = DownloadMockURLProtocol.makeSession()
    return ApiRepository(
      connection: Connection(
        url: baseURL, token: "t", identityName: nil, serverID: serverID),
      mode: .release,
      contentStore: contentStore,
      urlSession: session)
  }

  static func makeStore() throws -> (ContentStore, URL) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ApiRepoDownloadTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true)
    return (try ContentStore(root: root), root)
  }

  nonisolated static func okResponse(
    for request: URLRequest, suggested: String = "invoice.pdf"
  ) -> HTTPURLResponse {
    HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: [
        "Content-Disposition": "attachment; filename=\"\(suggested)\""
      ])!
  }

  nonisolated static func makeDocument(
    id: UInt = 7, modified: Date? = Date(timeIntervalSince1970: 1000)
  ) -> Document {
    Document(
      id: id, title: "doc", asn: nil, documentType: nil, correspondent: nil,
      created: Date(timeIntervalSince1970: 0), tags: [],
      added: nil, modified: modified, storagePath: nil)
  }

  nonisolated static func canonicalKey(
    for document: Document, original: Bool = false
  ) -> ContentStore.Key {
    ContentStore.Key(
      serverID: serverID,
      versionID: document.currentVersionID,
      kind: original ? .original : .archive)
  }

  // Atomic counter for request-count assertions across concurrent callbacks.
  final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func bump() { lock.withLock { _value += 1 } }
  }

  // Latest-value box for Sendable closures that mutate a captured value.
  final class LastValue<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ initial: T) { _value = initial }
    var value: T { lock.withLock { _value } }
    func set(_ v: T) { lock.withLock { _value = v } }
  }

  @Test
  func firstCallWritesToContentStore() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let payload = Data("HELLO".utf8)
    DownloadMockURLProtocol.responder = { req in (Self.okResponse(for: req), payload) }
    defer { DownloadMockURLProtocol.reset() }

    let url = try await repo.download(document: Self.makeDocument())

    #expect(url == store.url(for: Self.canonicalKey(for: Self.makeDocument())))
    #expect(try Data(contentsOf: url) == payload)
  }

  @Test
  func secondCallHitsCacheWithoutNetwork() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let counter = Counter()
    DownloadMockURLProtocol.responder = { req in
      counter.bump()
      return (Self.okResponse(for: req), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    _ = try await repo.download(document: Self.makeDocument())
    _ = try await repo.download(document: Self.makeDocument())

    #expect(counter.value == 1)
  }

  @Test
  func staleCacheRefetchesWhenModifiedChanges() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let counter = Counter()
    DownloadMockURLProtocol.responder = { req in
      counter.bump()
      return (Self.okResponse(for: req), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    _ = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 1)))
    _ = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 1)))
    _ = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 2)))

    #expect(counter.value == 2)
  }

  @Test
  func progressCallbackFires() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    DownloadMockURLProtocol.responder = { req in
      (Self.okResponse(for: req), Data(repeating: 0xab, count: 8192))
    }
    defer { DownloadMockURLProtocol.reset() }

    let lastProgress = Counter()
    _ = try await repo.download(
      document: Self.makeDocument(),
      progress: { _ in lastProgress.bump() })

    // We don't get strict guarantees from URLSession.download about how many
    // progress callbacks fire, but we should see at least one.
    #expect(lastProgress.value >= 1)
  }

  @Test
  func cacheHitFiresFinalProgress() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    DownloadMockURLProtocol.responder = { req in (Self.okResponse(for: req), Data()) }
    defer { DownloadMockURLProtocol.reset() }

    _ = try await repo.download(document: Self.makeDocument())

    let captured = LastValue<Double>(0)
    _ = try await repo.download(
      document: Self.makeDocument(),
      progress: { v in captured.set(v) })
    #expect(captured.value == 1.0)
  }

  @Test
  func unauthorizedResponseThrows() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    DownloadMockURLProtocol.responder = { req in
      (
        HTTPURLResponse(
          url: req.url!, statusCode: 401, httpVersion: "HTTP/1.1",
          headerFields: nil)!,
        Data()
      )
    }
    defer { DownloadMockURLProtocol.reset() }

    await #expect(throws: (any Error).self) {
      _ = try await repo.download(document: Self.makeDocument())
    }
  }

  @Test
  func documentWithNilModifiedAlwaysHitsNetwork() async throws {
    // No staleness signal → bypass ContentStore entirely. Two back-to-back
    // calls must each hit the network and the result must not appear in the
    // cache for a subsequent lookup.
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let counter = Counter()
    DownloadMockURLProtocol.responder = { req in
      counter.bump()
      return (Self.okResponse(for: req), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    let doc = Self.makeDocument(modified: nil)
    _ = try await repo.download(document: doc)
    _ = try await repo.download(document: doc)
    #expect(counter.value == 2)
    #expect(
      store.read(Self.canonicalKey(for: doc), freshAgainst: nil) == nil)
  }

  @Test
  func concurrentDownloadsForSameKeyDeduped() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let counter = Counter()
    DownloadMockURLProtocol.responder = { req in
      counter.bump()
      // Slight delay to ensure both callers reach the dedupe gate
      Thread.sleep(forTimeInterval: 0.05)
      return (Self.okResponse(for: req), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    async let a = repo.download(document: Self.makeDocument())
    async let b = repo.download(document: Self.makeDocument())
    let urls = try await [a, b]

    #expect(counter.value == 1)
    #expect(urls[0] == urls[1])
  }
}
