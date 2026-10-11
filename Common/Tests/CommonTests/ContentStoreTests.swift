//
//  ContentStoreTests.swift
//  Common
//

import Foundation
import Testing

@testable import Common

@Suite
struct ContentStoreTests {
  // Each test gets its own temp root via the package-internal init that
  // bypasses the app-group container lookup.
  static func makeStore() throws -> (ContentStore, URL) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ContentStoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true)
    let store = try ContentStore(root: root)
    return (store, root)
  }

  static func writeTempFile(_ bytes: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("payload-\(UUID().uuidString)")
    try bytes.write(to: url, options: .atomic)
    return url
  }

  static let serverA = UUID()
  static let serverB = UUID()

  /// The sidecar builds before the file index wrote next to each blob.
  static func writeLegacySidecar(_ store: ContentStore, _ key: ContentStore.Key, modified: Date?)
    throws
  {
    let url = store.url(for: key).deletingLastPathComponent()
      .appendingPathComponent("\(key.kind.rawValue).meta.json")
    let data = try JSONEncoder().encode(
      ContentStore.LegacySidecar(modified: modified, writtenAt: Date()))
    try data.write(to: url)
  }

  static func key(
    server: UUID = serverA, version: UInt = 42,
    kind: ContentStore.Kind = .archive
  ) -> ContentStore.Key {
    ContentStore.Key(serverID: server, versionID: version, kind: kind)
  }

  @Test
  func urlIsDeterministic() throws {
    let (store, _) = try Self.makeStore()
    let k = Self.key()
    #expect(store.url(for: k) == store.url(for: k))
    #expect(store.url(for: k) != store.url(for: Self.key(version: 43)))
    #expect(store.url(for: k) != store.url(for: Self.key(server: Self.serverB)))
    #expect(store.url(for: k) != store.url(for: Self.key(kind: .original)))
  }

  @Test
  func urlIncludesVersionInPath() throws {
    let (store, _) = try Self.makeStore()
    let url = store.url(for: Self.key(version: 35, kind: .archive))
    #expect(url.pathComponents.contains("35"))
    #expect(url.pathComponents.contains(Self.serverA.uuidString))
    #expect(url.lastPathComponent == "archive.pdf")
  }

  @Test
  func storeWritesBlobAtCanonicalPath() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("hello".utf8))

    let url = try store.store(Self.key(), movingFrom: temp)

    #expect(url == store.url(for: Self.key()))
    #expect(try Data(contentsOf: url) == Data("hello".utf8))
    #expect(store.exists(Self.key()))
  }

  @Test
  func storeOverwriteReplacesAtomically() throws {
    let (store, _) = try Self.makeStore()
    let first = try Self.writeTempFile(Data("first".utf8))
    try store.store(Self.key(), movingFrom: first)

    let second = try Self.writeTempFile(Data("second".utf8))
    let url = try store.store(Self.key(), movingFrom: second)
    #expect(try Data(contentsOf: url) == Data("second".utf8))
  }

  @Test
  func deleteRemovesBlobAndLegacySidecar() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    let url = try store.store(Self.key(), movingFrom: temp)
    try Self.writeLegacySidecar(store, Self.key(), modified: nil)

    try store.delete(Self.key())
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(!store.exists(Self.key()))
    #expect(store.readLegacySidecar(for: Self.key()) == nil)
  }

  @Test("A conditional delete leaves a blob written after the given date")
  func deleteUnlessNewer() throws {
    let (store, _) = try Self.makeStore()
    let url = try store.store(Self.key(), movingFrom: Self.writeTempFile(Data("x".utf8)))
    let written = try #require(
      try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

    #expect(store.delete(Self.key(), ifNotModifiedAfter: written.addingTimeInterval(-1)) == nil)
    #expect(store.exists(Self.key()))
    let removed = try #require(store.delete(Self.key(), ifNotModifiedAfter: written))
    #expect(removed > 0)
    #expect(!store.exists(Self.key()))
    #expect(store.delete(Self.key(), ifNotModifiedAfter: written) == nil)
  }

  @Test
  func deleteIsIdempotent() throws {
    let (store, _) = try Self.makeStore()
    try store.delete(Self.key())
    try store.delete(Self.key())
  }

  // MARK: - Index-backed storage

  @Test("store without a stamp writes the blob and no sidecar")
  func storeWritesNoSidecar() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("hello".utf8))

    let url = try store.store(Self.key(), movingFrom: temp)

    #expect(url == store.url(for: Self.key()))
    #expect(try Data(contentsOf: url) == Data("hello".utf8))
    #expect(store.readLegacySidecar(for: Self.key()) == nil)
    #expect(store.inventory().map(\.hasLegacySidecar) == [false])
  }

  @Test("storeData lands the bytes under the canonical name and leaves no temporary file")
  func storeDataWritesAtomically() throws {
    let (store, _) = try Self.makeStore()
    let key = Self.key(kind: .thumbnail)

    let url = try store.storeData(Data("png".utf8), for: key)

    #expect(url.lastPathComponent == "thumbnail.bin")
    #expect(try Data(contentsOf: url) == Data("png".utf8))
    let siblings = try FileManager.default.contentsOfDirectory(
      atPath: url.deletingLastPathComponent().path)
    #expect(siblings == ["thumbnail.bin"])
    // Replacing is as atomic as the first write.
    _ = try store.storeData(Data("png2".utf8), for: key)
    #expect(try Data(contentsOf: url) == Data("png2".utf8))
  }

  @Test("size reports the stored blob and nil for an absent one")
  func sizeOfBlob() throws {
    let (store, _) = try Self.makeStore()
    #expect(store.size(of: Self.key()) == nil)
    _ = try store.store(Self.key(), movingFrom: Self.writeTempFile(Data(repeating: 1, count: 100)))
    let size = try #require(store.size(of: Self.key()))
    #expect(size >= 100)
  }

  @Test("inventory lists every blob with its size and whether a legacy sidecar is next to it")
  func inventoryListsBlobs() throws {
    let (store, root) = try Self.makeStore()
    let legacy = Self.key(version: 1)
    let fresh = Self.key(version: 2, kind: .original)
    let other = Self.key(server: Self.serverB, version: 3, kind: .thumbnail)
    _ = try store.store(legacy, movingFrom: Self.writeTempFile(Data("a".utf8)))
    try Self.writeLegacySidecar(store, legacy, modified: Date())
    _ = try store.store(fresh, movingFrom: Self.writeTempFile(Data("bb".utf8)))
    _ = try store.storeData(Data("ccc".utf8), for: other)
    // Not this store's: skipped, not reported.
    let foreign = root.appendingPathComponent("Caches/ContentStore/not-a-uuid/keep.txt")
    try FileManager.default.createDirectory(
      at: foreign.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: foreign)

    let entries = store.inventory()

    #expect(Set(entries.map(\.key)) == [legacy, fresh, other])
    let legacyEntry = try #require(entries.first { $0.key == legacy })
    #expect(legacyEntry.hasLegacySidecar)
    #expect(legacyEntry.size > 0)
    #expect(legacyEntry.youngestModification != nil)
    #expect(entries.filter { $0.key != legacy }.allSatisfy { !$0.hasLegacySidecar })
    #expect(store.serverDirectories() == [Self.serverA, Self.serverB])
  }

  @Test("A legacy sidecar is read back with its sub-second stamp, then removed")
  func legacySidecar() throws {
    let (store, _) = try Self.makeStore()
    // Sub-second precision on purpose: paperless `modified` timestamps carry
    // fractional seconds, and the sidecar encoded dates as numbers to keep them.
    let modified = Date(timeIntervalSince1970: 1234.567891)
    _ = try store.store(Self.key(), movingFrom: Self.writeTempFile(Data("x".utf8)))
    try Self.writeLegacySidecar(store, Self.key(), modified: modified)

    let sidecar = try #require(store.readLegacySidecar(for: Self.key()))
    #expect(sidecar.modified == modified)

    store.removeLegacySidecar(for: Self.key())
    #expect(store.readLegacySidecar(for: Self.key()) == nil)
    #expect(store.exists(Self.key()))
  }

  @Test("removeEmptyDirectories drops emptied version and server directories only")
  func removeEmptyDirectories() throws {
    let (store, _) = try Self.makeStore()
    let gone = Self.key(version: 1)
    let kept = Self.key(server: Self.serverB, version: 2)
    let goneURL = try store.store(gone, movingFrom: Self.writeTempFile(Data("a".utf8)))
    let keptURL = try store.store(kept, movingFrom: Self.writeTempFile(Data("b".utf8)))
    try store.delete(gone)

    store.removeEmptyDirectories()

    #expect(!FileManager.default.fileExists(atPath: goneURL.deletingLastPathComponent().path))
    #expect(
      !FileManager.default.fileExists(
        atPath: goneURL.deletingLastPathComponent().deletingLastPathComponent().path))
    #expect(FileManager.default.fileExists(atPath: keptURL.path))
    #expect(store.serverDirectories() == [Self.serverB])
  }
}
