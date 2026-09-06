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

    let url = try store.store(
      Self.key(), movingFrom: temp,
      modified: Date(timeIntervalSince1970: 1000))

    #expect(url == store.url(for: Self.key()))
    #expect(try Data(contentsOf: url) == Data("hello".utf8))
  }

  @Test
  func readReturnsURLWhenModifiedMatches() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    // Sub-second precision on purpose: paperless `modified` timestamps carry
    // fractional seconds. If the sidecar dropped them (e.g. ISO-8601 whole-
    // second encoding), this read would miss and the cache would never hit.
    let modified = Date(timeIntervalSince1970: 1234.567891)
    try store.store(Self.key(), movingFrom: temp, modified: modified)

    #expect(store.read(Self.key(), freshAgainst: modified) != nil)
  }

  @Test
  func readReturnsNilWhenModifiedDiffers() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    try store.store(
      Self.key(), movingFrom: temp,
      modified: Date(timeIntervalSince1970: 1))

    #expect(
      store.read(Self.key(), freshAgainst: Date(timeIntervalSince1970: 2))
        == nil)
  }

  @Test
  func readReturnsNilWhenAnyModifiedIsNil() throws {
    // Both sides nil: still nil. A nil staleness signal is "we don't know",
    // not "fresh". Callers without a timestamp should bypass the cache.
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    try store.store(Self.key(), movingFrom: temp, modified: nil)
    #expect(store.read(Self.key(), freshAgainst: nil) == nil)

    // Sidecar has modified, caller doesn't: still nil.
    let (store2, _) = try Self.makeStore()
    let temp2 = try Self.writeTempFile(Data("x".utf8))
    try store2.store(
      Self.key(), movingFrom: temp2,
      modified: Date(timeIntervalSince1970: 1))
    #expect(store2.read(Self.key(), freshAgainst: nil) == nil)

    // Caller has modified, sidecar doesn't: still nil.
    let (store3, _) = try Self.makeStore()
    let temp3 = try Self.writeTempFile(Data("x".utf8))
    try store3.store(Self.key(), movingFrom: temp3, modified: nil)
    #expect(
      store3.read(Self.key(), freshAgainst: Date(timeIntervalSince1970: 1))
        == nil)
  }

  @Test
  func readReturnsNilWhenSidecarMissing() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    let modified = Date(timeIntervalSince1970: 1234)
    let url = try store.store(
      Self.key(), movingFrom: temp, modified: modified)

    // Wipe the sidecar but leave the blob. read() must NOT serve a hit
    // because it can no longer validate freshness, even when the caller
    // supplies a real timestamp.
    let sidecar = url.deletingLastPathComponent()
      .appendingPathComponent("archive.meta.json")
    try FileManager.default.removeItem(at: sidecar)
    #expect(FileManager.default.fileExists(atPath: url.path))

    #expect(store.read(Self.key(), freshAgainst: modified) == nil)
  }

  @Test
  func storeOverwriteReplacesAtomically() throws {
    let (store, _) = try Self.makeStore()
    let first = try Self.writeTempFile(Data("first".utf8))
    try store.store(Self.key(), movingFrom: first, modified: nil)

    let second = try Self.writeTempFile(Data("second".utf8))
    let url = try store.store(Self.key(), movingFrom: second, modified: nil)
    #expect(try Data(contentsOf: url) == Data("second".utf8))
  }

  @Test
  func deleteRemovesBlobAndSidecar() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    let url = try store.store(Self.key(), movingFrom: temp, modified: nil)

    try store.delete(Self.key())
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(store.read(Self.key(), freshAgainst: nil) == nil)
  }

  @Test
  func deleteIsIdempotent() throws {
    let (store, _) = try Self.makeStore()
    try store.delete(Self.key())
    try store.delete(Self.key())
  }

  // MARK: - Reclamation

  /// Every reclaim test writes its blobs "now" and then sweeps with a clock two
  /// grace periods ahead, rather than backdating files: it exercises the same
  /// comparison without depending on the filesystem's timestamp granularity.
  private static var aged: Date {
    Date().addingTimeInterval(2 * ContentStore.reclaimGracePeriod)
  }

  private static func write(_ store: ContentStore, _ key: ContentStore.Key) throws -> URL {
    try store.store(
      key, movingFrom: writeTempFile(Data("payload".utf8)),
      modified: Date(timeIntervalSince1970: 1000))
  }

  @Test("Reclaim keeps the blob of a version the database still references")
  func reclaimKeepsLiveVersion() throws {
    let (store, _) = try Self.makeStore()
    let live = Self.key(version: 9)
    let url = try Self.write(store, live)

    let report = store.reclaim(
      retaining: [Self.serverA: [9]], now: Self.aged)

    #expect(report.removedFiles == 0)
    #expect(report.examinedVersions == 1)
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(store.read(live, freshAgainst: Date(timeIntervalSince1970: 1000)) == url)
  }

  @Test("Reclaim drops a superseded version, its sidecar and its directory")
  func reclaimRemovesSupersededVersion() throws {
    let (store, _) = try Self.makeStore()
    let superseded = Self.key(version: 4)
    let current = Self.key(version: 9)
    let old = try Self.write(store, superseded)
    let new = try Self.write(store, current)

    let report = store.reclaim(retaining: [Self.serverA: [9]], now: Self.aged)

    // Blob + sidecar for the one dead version.
    #expect(report.removedFiles == 2)
    #expect(report.reclaimedBytes > 0)
    #expect(report.examinedVersions == 2)
    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(!FileManager.default.fileExists(atPath: old.deletingLastPathComponent().path))
    #expect(FileManager.default.fileExists(atPath: new.path))
  }

  @Test("Reclaim drops content of a document, and a server, the database no longer knows")
  func reclaimRemovesDeletedDocumentAndServer() throws {
    let (store, _) = try Self.makeStore()
    let deletedDocument = try Self.write(store, Self.key(version: 4))
    let removedServer = try Self.write(store, Self.key(server: Self.serverB, version: 7))
    let kept = try Self.write(store, Self.key(version: 9))

    // Server A still has one document (version 9); server B's connection is
    // gone entirely, so it appears in the map not at all.
    let report = store.reclaim(retaining: [Self.serverA: [9]], now: Self.aged)

    #expect(report.removedFiles == 4)
    #expect(!FileManager.default.fileExists(atPath: deletedDocument.path))
    #expect(!FileManager.default.fileExists(atPath: removedServer.path))
    // The whole server directory goes, not just its contents.
    #expect(
      !FileManager.default.fileExists(
        atPath: removedServer.deletingLastPathComponent().deletingLastPathComponent().path))
    #expect(FileManager.default.fileExists(atPath: kept.path))
  }

  @Test("Reclaim leaves an unreferenced blob alone while it is inside the grace period")
  func reclaimKeepsFreshBlob() throws {
    let (store, _) = try Self.makeStore()
    let fresh = try Self.write(store, Self.key(version: 4))

    // Default clock: the file was written moments ago, so it is inside the
    // window in which a concurrent writer may still be about to reference it.
    let report = store.reclaim(retaining: [:])

    #expect(report.removedFiles == 0)
    #expect(report.keptRecent == 1)
    #expect(FileManager.default.fileExists(atPath: fresh.path))

    // The same sweep with an aged clock does remove it, so the retention above
    // is the grace period and nothing else.
    #expect(store.reclaim(retaining: [:], now: Self.aged).removedFiles == 2)
    #expect(!FileManager.default.fileExists(atPath: fresh.path))
  }

  @Test("Reclaim tolerates a file that vanishes before it gets there")
  func reclaimToleratesMissingFile() throws {
    let (store, _) = try Self.makeStore()
    let key = Self.key(version: 4)
    let url = try Self.write(store, key)
    // Stands in for another process (or a `purge()`) removing the blob between
    // the directory listing and the unlink; the orphaned sidecar must still go.
    try FileManager.default.removeItem(at: url)

    let report = store.reclaim(retaining: [:], now: Self.aged)

    #expect(report.removedFiles == 1)
    #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
  }

  @Test("Reclaim never touches files it did not write")
  func reclaimIgnoresForeignEntries() throws {
    let (store, root) = try Self.makeStore()
    _ = try Self.write(store, Self.key(version: 4))
    let contentRoot = root.appendingPathComponent("Caches/ContentStore", isDirectory: true)
    let foreign = contentRoot.appendingPathComponent("not-a-uuid", isDirectory: true)
    try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
    let foreignFile = foreign.appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: foreignFile)

    _ = store.reclaim(retaining: [:], now: Self.aged)

    #expect(FileManager.default.fileExists(atPath: foreignFile.path))
  }
}
