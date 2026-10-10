import Common
import DataModel
import Foundation
import Nuke
import Testing

@testable import AppShared

/// The thumbnail id and the content-store-backed Nuke data cache.
@Suite
struct ThumbnailCacheTests {
  private static let server = UUID()

  private func document(_ id: UInt, versions: [UInt] = []) -> Document {
    Document(
      id: id, title: "d\(id)", created: Date(timeIntervalSince1970: 0), tags: [],
      versions: versions.map {
        DocumentVersion(id: $0, added: Date(timeIntervalSince1970: 0), isRoot: $0 == versions.first)
      })
  }

  private func makeStore() throws -> ContentStore {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ThumbnailCacheTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return try ContentStore(root: root)
  }

  /// A `FileIndex` in a dictionary.
  private actor Index: FileIndex {
    var entries: [ContentStore.Key: FileIndexEntry] = [:]

    func freshEntry(for key: ContentStore.Key, modified: Date) async throws -> FileIndexEntry? {
      entries[key]
    }

    func recordStore(
      _ key: ContentStore.Key, documentID: UInt, size: Int64, modified: Date?, checksum: String?,
      storedAt: Date
    ) async throws {
      entries[key] = FileIndexEntry(
        key: key, documentID: documentID, size: size, modified: modified, storedAt: storedAt,
        lastAccessedAt: nil)
    }

    func recordAccess(_ key: ContentStore.Key, at date: Date) async throws {}

    func forget(_ key: ContentStore.Key) async throws {
      entries[key] = nil
    }

    func entry(for key: ContentStore.Key) async -> FileIndexEntry? {
      for _ in 0..<100 where entries[key] == nil {
        try? await Task.sleep(for: .milliseconds(10))
      }
      return entries[key]
    }

    func forgotten(_ key: ContentStore.Key) async -> Bool {
      for _ in 0..<100 where entries[key] != nil {
        try? await Task.sleep(for: .milliseconds(10))
      }
      return entries[key] == nil
    }
  }

  // MARK: - Id

  @Test("The id names the server, document and current version, and parses back")
  func idRoundTrip() throws {
    let id = ThumbnailImageID.make(serverID: Self.server, document: document(7, versions: [7, 91]))

    let parsed = try #require(ThumbnailImageID.parse(id))
    #expect(parsed.key == ContentStore.Key(serverID: Self.server, versionID: 91, kind: .thumbnail))
    #expect(parsed.documentID == 7)
    // Without versions the document id is the version.
    let plain = ThumbnailImageID.make(serverID: Self.server, document: document(7))
    #expect(ThumbnailImageID.parse(plain)?.key.versionID == 7)
  }

  @Test("Anything but an exact id is rejected: processor suffixes, URLs, bad ids")
  func idRejectsOthers() {
    let id = ThumbnailImageID.make(serverID: Self.server, document: document(7))
    #expect(ThumbnailImageID.parse(id + "com.github.kean.nuke.resize(…)") == nil)
    #expect(ThumbnailImageID.parse(id + "/") == nil)
    #expect(ThumbnailImageID.parse("https://example.com/api/documents/7/thumb") == nil)
    #expect(ThumbnailImageID.parse("swift-paperless:thumbnail/not-a-uuid/7/7") == nil)
    #expect(
      ThumbnailImageID.parse("swift-paperless:thumbnail/\(Self.server.uuidString)/x/7") == nil)
  }

  // MARK: - Data cache

  @Test("A stored thumbnail lands at the version's file and in the index")
  func storeAndRead() async throws {
    let store = try makeStore()
    let index = Index()
    let cache = ContentStoreDataCache(store: store, index: index)
    let id = ThumbnailImageID.make(serverID: Self.server, document: document(7, versions: [7, 91]))
    let key = ContentStore.Key(serverID: Self.server, versionID: 91, kind: .thumbnail)
    #expect(!cache.containsData(for: id))
    #expect(cache.cachedData(for: id) == nil)

    cache.storeData(Data("png".utf8), for: id)

    let entry = try #require(await index.entry(for: key))
    #expect(entry.documentID == 7)
    #expect(entry.size == store.size(of: key))
    #expect(entry.modified == nil)
    #expect(store.url(for: key).lastPathComponent == "thumbnail.bin")
    #expect(cache.containsData(for: id))
    #expect(cache.cachedData(for: id) == Data("png".utf8))

    cache.removeData(for: id)
    #expect(await index.forgotten(key))
    #expect(!cache.containsData(for: id))
  }

  @Test("A key that is not a thumbnail id is neither read nor written")
  func foreignKeysAreIgnored() async throws {
    let store = try makeStore()
    let index = Index()
    let cache = ContentStoreDataCache(store: store, index: index)
    let processed = ThumbnailImageID.make(serverID: Self.server, document: document(7)) + "resize"

    cache.storeData(Data("png".utf8), for: processed)
    cache.storeData(Data("png".utf8), for: "https://example.com/api/documents/7/thumb")
    try await Task.sleep(for: .milliseconds(50))

    #expect(store.inventory().isEmpty)
    #expect(await index.entries.isEmpty)
    #expect(cache.cachedData(for: processed) == nil)
    #expect(!cache.containsData(for: processed))
  }
}
