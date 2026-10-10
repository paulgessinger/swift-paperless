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
    struct Entry: Equatable {
      var documentID: UInt
      var size: Int64
      var modified: Date?
    }

    var entries: [ContentStore.Key: Entry] = [:]

    func isFresh(_ key: ContentStore.Key, modified: Date) async throws -> Bool {
      entries[key]?.modified == modified
    }

    func recordStore(
      _ key: ContentStore.Key, documentID: UInt, size: Int64, modified: Date?, checksum: String?,
      storedAt: Date
    ) async throws {
      entries[key] = Entry(documentID: documentID, size: size, modified: modified)
    }

    func recordAccess(_ key: ContentStore.Key, at date: Date) async throws {}

    func forget(_ key: ContentStore.Key) async throws {
      entries[key] = nil
    }

    func entry(for key: ContentStore.Key) async -> Entry? {
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

  @Test("An id with a processor suffix is a variant; an exact id or a foreign key is not")
  func idVariants() {
    let id = ThumbnailImageID.make(serverID: Self.server, document: document(7, versions: [7, 91]))
    #expect(ThumbnailImageID.isVariant(id + "com.github.kean/nuke/resize?s=(130.0, 9.0)"))
    #expect(!ThumbnailImageID.isVariant(id))
    #expect(!ThumbnailImageID.isVariant("https://example.com/api/documents/7/thumb"))
    #expect(!ThumbnailImageID.isVariant("swift-paperless:thumbnail/not-a-uuid/7/7resize"))
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

  @Test("A resized variant goes to the variant cache, not the store or the index")
  func variantsAreCachedApart() async throws {
    let store = try makeStore()
    let index = Index()
    let variants = try ThumbnailVariantCache.make(
      at: FileManager.default.temporaryDirectory
        .appendingPathComponent("ThumbnailCacheTests-variants-\(UUID().uuidString)"))
    let cache = ContentStoreDataCache(store: store, index: index, variants: variants)
    let id = ThumbnailImageID.make(serverID: Self.server, document: document(7))
    let resized = id + "com.github.kean/nuke/resize?s=(130.0, 9.0)"
    #expect(!cache.containsData(for: resized))

    cache.storeData(Data("small".utf8), for: resized)
    cache.storeData(Data("png".utf8), for: id)
    let key = ContentStore.Key(serverID: Self.server, versionID: 7, kind: .thumbnail)
    _ = await index.entry(for: key)

    #expect(cache.containsData(for: resized))
    #expect(cache.cachedData(for: resized) == Data("small".utf8))
    #expect(variants.cachedData(for: resized) == Data("small".utf8))
    #expect(store.inventory().map(\.key) == [key])
    #expect(await index.entries.count == 1)

    // The wipe empties the variants and leaves the store's files to the purge.
    cache.removeAll()
    #expect(!cache.containsData(for: resized))
    #expect(cache.containsData(for: id))

    cache.storeData(Data("again".utf8), for: resized)
    cache.removeData(for: resized)
    #expect(!cache.containsData(for: resized))
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
