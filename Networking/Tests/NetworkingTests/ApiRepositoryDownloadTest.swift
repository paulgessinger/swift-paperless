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

/// A `FileIndex` in a dictionary, recording what the repository tells it.
actor InMemoryFileIndex: FileIndex {
  struct Entry: Equatable {
    var documentID: UInt
    var size: Int64
    var modified: Date?
    var checksum: String?
    var storedAt: Date
  }

  private(set) var entries: [ContentStore.Key: Entry] = [:]
  private(set) var accesses: [ContentStore.Key] = []

  func isFresh(_ key: ContentStore.Key, modified: Date) async throws -> Bool {
    entries[key]?.modified == modified
  }

  func storedChecksum(_ key: ContentStore.Key) async throws -> String? {
    entries[key]?.checksum
  }

  func recordStore(
    _ key: ContentStore.Key, documentID: UInt, size: Int64, modified: Date?, checksum: String?,
    storedAt: Date
  ) async throws {
    entries[key] = Entry(
      documentID: documentID, size: size, modified: modified, checksum: checksum,
      storedAt: storedAt)
  }

  func recordAccess(_ key: ContentStore.Key, at date: Date) async throws {
    accesses.append(key)
  }

  func forget(_ key: ContentStore.Key) async throws {
    entries[key] = nil
  }

  /// Wait for the fire-and-forget access record to land.
  func accessCount() async -> Int {
    for _ in 0..<50 where accesses.isEmpty {
      try? await Task.sleep(for: .milliseconds(10))
    }
    return accesses.count
  }
}

@MainActor
@Suite(.serialized)
struct ApiRepositoryDownloadTest {
  nonisolated static let baseURL = URL(string: "https://example.com")!
  nonisolated static let serverID = UUID(
    uuidString: "11111111-2222-3333-4444-555555555555")!

  static func makeRepo(contentStore: ContentStore, index: (any FileIndex)? = InMemoryFileIndex())
    -> ApiRepository
  {
    let session = DownloadMockURLProtocol.makeSession()
    return ApiRepository(
      connection: Connection(
        url: baseURL, token: "t", identityName: nil, serverID: serverID),
      mode: .release,
      contentStore: contentStore,
      fileIndex: index,
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
    id: UInt = 7, modified: Date? = Date(timeIntervalSince1970: 1000),
    originalFileName: String? = "doc.pdf", archivedFileName: String? = "doc.pdf",
    versions: [DocumentVersion] = []
  ) -> Document {
    Document(
      id: id, title: "doc", asn: nil, documentType: nil, correspondent: nil,
      created: Date(timeIntervalSince1970: 0), tags: [],
      added: nil, modified: modified, originalFileName: originalFileName,
      archivedFileName: archivedFileName, storagePath: nil,
      versions: versions)
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
  func firstCallWritesToContentStoreAndRecordsTheFile() async throws {
    let (store, _) = try Self.makeStore()
    let index = InMemoryFileIndex()
    let repo = Self.makeRepo(contentStore: store, index: index)
    let payload = Data("HELLO".utf8)
    DownloadMockURLProtocol.responder = { req in (Self.okResponse(for: req), payload) }
    defer { DownloadMockURLProtocol.reset() }

    let document = Self.makeDocument(
      versions: [
        DocumentVersion(
          id: 7, added: Date(timeIntervalSince1970: 1000), checksum: "abc", isRoot: true)
      ])
    let url = try await repo.download(document: document)

    let key = Self.canonicalKey(for: document)
    #expect(url == store.url(for: key))
    #expect(try Data(contentsOf: url) == payload)
    #expect(store.readLegacySidecar(for: key) == nil)
    let entry = try #require(await index.entries[key])
    #expect(entry.documentID == 7)
    #expect(entry.size == store.size(of: key))
    #expect(entry.size >= Int64(payload.count))
    #expect(entry.modified == document.modified)
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
  func cacheHitRecordsAnAccess() async throws {
    let (store, _) = try Self.makeStore()
    let index = InMemoryFileIndex()
    let repo = Self.makeRepo(contentStore: store, index: index)
    DownloadMockURLProtocol.responder = { req in (Self.okResponse(for: req), Data("X".utf8)) }
    defer { DownloadMockURLProtocol.reset() }

    _ = try await repo.download(document: Self.makeDocument())
    #expect(await index.accesses.isEmpty)
    _ = try await repo.download(document: Self.makeDocument())

    #expect(await index.accessCount() == 1)
  }

  @Test
  func indexedFileThatWentMissingIsAMiss() async throws {
    let (store, _) = try Self.makeStore()
    let index = InMemoryFileIndex()
    let repo = Self.makeRepo(contentStore: store, index: index)
    let counter = Counter()
    DownloadMockURLProtocol.responder = { req in
      counter.bump()
      return (Self.okResponse(for: req), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    let url = try await repo.download(document: Self.makeDocument())
    try FileManager.default.removeItem(at: url)
    let again = try await repo.download(document: Self.makeDocument())

    #expect(counter.value == 2)
    #expect(again == url)
    #expect(FileManager.default.fileExists(atPath: url.path))
  }

  @Test
  func withoutAnIndexNothingIsCached() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store, index: nil)
    let counter = Counter()
    DownloadMockURLProtocol.responder = { req in
      counter.bump()
      return (Self.okResponse(for: req), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    _ = try await repo.download(document: Self.makeDocument())
    _ = try await repo.download(document: Self.makeDocument())

    #expect(counter.value == 2)
    #expect(!store.exists(Self.canonicalKey(for: Self.makeDocument())))
  }

  @Test
  func staleCacheRefetchesWhenModifiedChanges() async throws {
    let (store, _) = try Self.makeStore()
    let index = InMemoryFileIndex()
    let repo = Self.makeRepo(contentStore: store, index: index)
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
    let entry = try #require(await index.entries[Self.canonicalKey(for: Self.makeDocument())])
    #expect(entry.modified == Date(timeIntervalSince1970: 2))
  }

  nonisolated static func response(
    for request: URLRequest, status: Int = 200, etag: String? = nil
  ) -> HTTPURLResponse {
    var headers = ["Content-Disposition": "inline; filename=\"invoice.pdf\""]
    if let etag { headers["ETag"] = etag }
    return HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
  }

  @Test
  func fetchesFromThePreviewEndpoint() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let paths = LastValue<[String]>([])
    DownloadMockURLProtocol.responder = { req in
      paths.set(paths.value + [req.url!.path])
      return (Self.okResponse(for: req), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    _ = try await repo.download(document: Self.makeDocument())

    #expect(paths.value.count == 1)
    #expect(paths.value.first?.hasPrefix("/api/documents/7/preview") == true)
  }

  @Test(
    arguments: [
      (false, "doc.pdf", "doc.pdf", nil), (true, "doc.pdf", "doc.pdf", "true"),
      (false, "doc.jpg", nil, "true"),
      // Older servers omit both filenames; an archive may still exist.
      (false, nil, nil, nil),
    ] as [(Bool, String?, String?, String?)])
  func requestsTheOriginalWhenThereIsNoArchive(
    original: Bool, originalFileName: String?, archivedFileName: String?, expected: String?
  ) async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let query = LastValue<String?>(nil)
    DownloadMockURLProtocol.responder = { req in
      query.set(
        URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?
          .queryItems?.first { $0.name == "original" }?.value)
      return (Self.okResponse(for: req), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    let document = Self.makeDocument(
      originalFileName: originalFileName, archivedFileName: archivedFileName)
    let url = try await repo.download(document: document, original: original)

    #expect(query.value == expected)
    #expect(url == store.url(for: Self.canonicalKey(for: document, original: original)))
  }

  @Test
  func recordsTheETagAsTheChecksum() async throws {
    let (store, _) = try Self.makeStore()
    let index = InMemoryFileIndex()
    let repo = Self.makeRepo(contentStore: store, index: index)
    DownloadMockURLProtocol.responder = { req in
      (Self.response(for: req, etag: "\"archive-md5\""), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    let document = Self.makeDocument()
    _ = try await repo.download(document: document)

    #expect(await index.entries[Self.canonicalKey(for: document)]?.checksum == "archive-md5")
  }

  @Test
  func unchangedFileIsRevalidatedWithoutABody() async throws {
    let (store, _) = try Self.makeStore()
    let index = InMemoryFileIndex()
    let repo = Self.makeRepo(contentStore: store, index: index)
    let validators = LastValue<[String?]>([])
    DownloadMockURLProtocol.responder = { req in
      let validator = req.value(forHTTPHeaderField: "If-None-Match")
      validators.set(validators.value + [validator])
      if validator == "\"archive-md5\"" {
        return (Self.response(for: req, status: 304, etag: "\"archive-md5\""), Data())
      }
      return (Self.response(for: req, etag: "\"archive-md5\""), Data("ORIGINAL".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    let first = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 1)))
    let second = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 2)))

    #expect(validators.value == [nil, "\"archive-md5\""])
    #expect(second == first)
    #expect(try Data(contentsOf: second) == Data("ORIGINAL".utf8))
    let entry = try #require(await index.entries[Self.canonicalKey(for: Self.makeDocument())])
    #expect(entry.modified == Date(timeIntervalSince1970: 2))
    #expect(entry.checksum == "archive-md5")

    // The refreshed row makes the next open a local hit.
    _ = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 2)))
    #expect(validators.value.count == 2)
  }

  @Test
  func changedFileReplacesTheStoredOne() async throws {
    let (store, _) = try Self.makeStore()
    let index = InMemoryFileIndex()
    let repo = Self.makeRepo(contentStore: store, index: index)
    let etag = LastValue("\"v1\"")
    let body = LastValue(Data("ONE".utf8))
    DownloadMockURLProtocol.responder = { req in
      if req.value(forHTTPHeaderField: "If-None-Match") == etag.value {
        return (Self.response(for: req, status: 304, etag: etag.value), Data())
      }
      return (Self.response(for: req, etag: etag.value), body.value)
    }
    defer { DownloadMockURLProtocol.reset() }

    _ = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 1)))
    etag.set("\"v2\"")
    body.set(Data("TWO".utf8))
    let url = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 2)))

    #expect(try Data(contentsOf: url) == Data("TWO".utf8))
    #expect(await index.entries[Self.canonicalKey(for: Self.makeDocument())]?.checksum == "v2")
  }

  @Test
  func noValidatorWithoutAStoredChecksum() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let validators = LastValue<[String?]>([])
    DownloadMockURLProtocol.responder = { req in
      validators.set(validators.value + [req.value(forHTTPHeaderField: "If-None-Match")])
      return (Self.okResponse(for: req), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    _ = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 1)))
    _ = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 2)))

    #expect(validators.value == [nil, nil])
  }

  @Test
  func revalidatedFileOutlivesAReclaimOfTheOldRow() async throws {
    let (store, _) = try Self.makeStore()
    let index = InMemoryFileIndex()
    let repo = Self.makeRepo(contentStore: store, index: index)
    DownloadMockURLProtocol.responder = { req in
      if req.value(forHTTPHeaderField: "If-None-Match") == "\"md5\"" {
        return (Self.response(for: req, status: 304, etag: "\"md5\""), Data())
      }
      return (Self.response(for: req, etag: "\"md5\""), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }
    let key = Self.canonicalKey(for: Self.makeDocument())

    _ = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 1)))
    let oldRow = try #require(await index.entries[key])
    // The file keeps the date of its first write, which is before the row.
    try store.touch(key, at: oldRow.storedAt.addingTimeInterval(-10))

    let url = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 2)))

    // A pass that claimed the old row before the 304 was recorded leaves the
    // file alone, and the new row dates it.
    #expect(store.delete(key, ifNotModifiedAfter: oldRow.storedAt) == nil)
    #expect(try Data(contentsOf: url) == Data("X".utf8))
    let newRow = try #require(await index.entries[key])
    let modified = try #require(
      try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    #expect(abs(modified.timeIntervalSince(newRow.storedAt)) < 1)
  }

  @Test
  func notModifiedForAReclaimedFileFetchesInFull() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let validators = LastValue<[String?]>([])
    let storeRef = store
    let key = Self.canonicalKey(for: Self.makeDocument())
    DownloadMockURLProtocol.responder = { req in
      let validator = req.value(forHTTPHeaderField: "If-None-Match")
      validators.set(validators.value + [validator])
      if validator != nil {
        // The reclaimer removes the file while the request is out.
        try? storeRef.delete(key)
        return (Self.response(for: req, status: 304, etag: "\"md5\""), Data())
      }
      return (Self.response(for: req, etag: "\"md5\""), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    _ = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 1)))
    let url = try await repo.download(
      document: Self.makeDocument(modified: Date(timeIntervalSince1970: 2)))

    #expect(validators.value == [nil, "\"md5\"", nil])
    #expect(try Data(contentsOf: url) == Data("X".utf8))
  }

  @Test(
    arguments: [
      ("\"abc\"", "abc"), ("W/\"abc\"", "abc"), ("abc", "abc"), ("\"\"", nil),
    ] as [(String, String?)])
  func entityTagParsing(header: String, expected: String?) {
    let response = HTTPURLResponse(
      url: Self.baseURL, statusCode: 200, httpVersion: nil, headerFields: ["ETag": header])!
    #expect(ApiRepository.entityTag(of: response) == expected)
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
    let index = InMemoryFileIndex()
    let repo = Self.makeRepo(contentStore: store, index: index)
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
    #expect(!store.exists(Self.canonicalKey(for: doc)))
    #expect(await index.entries.isEmpty)
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

  // A caller that joins an in-flight download must be fed progress too — it
  // used to see none at all and rendered a bar frozen at zero for the whole
  // download.
  @Test
  func joinedCallerReceivesProgress() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let counter = Counter()
    DownloadMockURLProtocol.responder = { req in
      counter.bump()
      // Long enough for the second caller to reach the dedupe gate before any
      // bytes flow.
      Thread.sleep(forTimeInterval: 0.05)
      return (Self.okResponse(for: req), Data(repeating: 0xab, count: 1 << 20))
    }
    defer { DownloadMockURLProtocol.reset() }

    let firstProgress = Counter()
    let secondProgress = Counter()
    async let a = repo.download(
      document: Self.makeDocument(), progress: { _ in firstProgress.bump() })
    async let b = repo.download(
      document: Self.makeDocument(), progress: { _ in secondProgress.bump() })
    let urls = try await [a, b]

    #expect(counter.value == 1)
    #expect(urls[0] == urls[1])
    #expect(firstProgress.value >= 1)
    #expect(secondProgress.value >= 1)
  }

  // Coalescing is keyed on the staleness stamp too. Two callers holding the
  // same version but different `modified` must not share a task — the winner
  // would otherwise record its own stamp in the index for both, and a blob
  // recorded as fresher than it is would then pass the freshness lookup.
  @Test
  func concurrentDownloadsWithDifferentModifiedNotDeduped() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let counter = Counter()
    DownloadMockURLProtocol.responder = { req in
      counter.bump()
      Thread.sleep(forTimeInterval: 0.05)
      return (Self.okResponse(for: req), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    let older = Self.makeDocument(modified: Date(timeIntervalSince1970: 1000))
    let newer = Self.makeDocument(modified: Date(timeIntervalSince1970: 2000))
    async let a = repo.download(document: older)
    async let b = repo.download(document: newer)
    _ = try await [a, b]

    #expect(counter.value == 2)
  }

  // Nuke keys its thumbnail data cache on the URL string, and the ContentStore
  // path is keyed separately, so a redundant `?version=` on the request URL
  // buys nothing and would invalidate every cached thumbnail on upgrade.
  @Test
  func noVersionQueryWhenServerReportsNoVersions() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let seenURL = LastValue<URL?>(nil)
    DownloadMockURLProtocol.responder = { req in
      seenURL.set(req.url)
      return (Self.okResponse(for: req), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    _ = try await repo.download(document: Self.makeDocument(versions: []))
    let query =
      URLComponents(url: try #require(seenURL.value), resolvingAgainstBaseURL: false)?
      .queryItems ?? []
    #expect(!query.contains { $0.name == "version" })
  }

  @Test
  func versionQuerySentWhenServerReportsVersions() async throws {
    let (store, _) = try Self.makeStore()
    let repo = Self.makeRepo(contentStore: store)
    let seenURL = LastValue<URL?>(nil)
    DownloadMockURLProtocol.responder = { req in
      seenURL.set(req.url)
      return (Self.okResponse(for: req), Data("X".utf8))
    }
    defer { DownloadMockURLProtocol.reset() }

    let doc = Self.makeDocument(
      id: 7,
      versions: [
        DocumentVersion(id: 7, added: Date(timeIntervalSince1970: 1000), isRoot: true),
        DocumentVersion(id: 91, added: Date(timeIntervalSince1970: 2000), isRoot: false),
      ])
    _ = try await repo.download(document: doc)
    let query =
      URLComponents(url: try #require(seenURL.value), resolvingAgainstBaseURL: false)?
      .queryItems ?? []
    #expect(query.contains(URLQueryItem(name: "version", value: "91")))
  }
}
