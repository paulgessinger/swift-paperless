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
    server: UUID = serverA, doc: UInt = 42, version: String = "current",
    kind: ContentStore.Kind = .archive
  ) -> ContentStore.Key {
    ContentStore.Key(
      serverID: server, documentRemoteID: doc, versionID: version, kind: kind)
  }

  @Test
  func urlIsDeterministic() throws {
    let (store, _) = try Self.makeStore()
    let k = Self.key()
    #expect(store.url(for: k) == store.url(for: k))
    #expect(store.url(for: k) != store.url(for: Self.key(doc: 43)))
    #expect(store.url(for: k) != store.url(for: Self.key(server: Self.serverB)))
    #expect(store.url(for: k) != store.url(for: Self.key(kind: .original)))
    #expect(store.url(for: k) != store.url(for: Self.key(version: "other")))
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
    let modified = Date(timeIntervalSince1970: 1234)
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
  func readReturnsURLWhenBothNil() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    try store.store(Self.key(), movingFrom: temp, modified: nil)
    #expect(store.read(Self.key(), freshAgainst: nil) != nil)
  }

  @Test
  func readReturnsNilWhenOnlyOneSideIsNil() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    try store.store(
      Self.key(), movingFrom: temp,
      modified: Date(timeIntervalSince1970: 1))
    #expect(store.read(Self.key(), freshAgainst: nil) == nil)

    let (store2, _) = try Self.makeStore()
    let temp2 = try Self.writeTempFile(Data("x".utf8))
    try store2.store(Self.key(), movingFrom: temp2, modified: nil)
    #expect(
      store2.read(Self.key(), freshAgainst: Date(timeIntervalSince1970: 1))
        == nil)
  }

  @Test
  func readReturnsNilWhenSidecarMissing() throws {
    let (store, root) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    let url = try store.store(Self.key(), movingFrom: temp, modified: nil)

    // Wipe the sidecar but leave the blob. read() must NOT serve a hit
    // because it can no longer validate freshness.
    let sidecar = url.deletingLastPathComponent()
      .appendingPathComponent("archive.meta.json")
    try FileManager.default.removeItem(at: sidecar)
    #expect(FileManager.default.fileExists(atPath: url.path))
    _ = root  // silence unused warning

    #expect(store.read(Self.key(), freshAgainst: nil) == nil)
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
}
