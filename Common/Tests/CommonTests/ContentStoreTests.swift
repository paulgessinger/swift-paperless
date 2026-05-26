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
  func storeWritesBlobAndReturnsHit() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("hello".utf8))

    let hit = try store.store(
      Self.key(), movingFrom: temp,
      modified: Date(timeIntervalSince1970: 1000),
      suggestedFilename: "invoice.pdf")

    #expect(FileManager.default.fileExists(atPath: hit.canonicalURL.path))
    #expect(FileManager.default.fileExists(atPath: hit.friendlyURL.path))
    #expect(hit.friendlyURL.lastPathComponent == "invoice.pdf")
    #expect(try Data(contentsOf: hit.canonicalURL) == Data("hello".utf8))
    #expect(try Data(contentsOf: hit.friendlyURL) == Data("hello".utf8))
  }

  @Test
  func readReturnsHitWhenModifiedMatches() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    let modified = Date(timeIntervalSince1970: 1234)
    try store.store(
      Self.key(), movingFrom: temp, modified: modified,
      suggestedFilename: "a.pdf")

    let hit = store.read(Self.key(), freshAgainst: modified)
    #expect(hit != nil)
    #expect(hit?.suggestedFilename == "a.pdf")
  }

  @Test
  func readReturnsNilWhenModifiedDiffers() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    try store.store(
      Self.key(), movingFrom: temp,
      modified: Date(timeIntervalSince1970: 1),
      suggestedFilename: "a.pdf")

    #expect(
      store.read(Self.key(), freshAgainst: Date(timeIntervalSince1970: 2))
        == nil)
  }

  @Test
  func readReturnsHitWhenBothNil() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    try store.store(
      Self.key(), movingFrom: temp, modified: nil,
      suggestedFilename: "a.pdf")
    #expect(store.read(Self.key(), freshAgainst: nil) != nil)
  }

  @Test
  func readReturnsNilWhenOnlyOneSideIsNil() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    try store.store(
      Self.key(), movingFrom: temp,
      modified: Date(timeIntervalSince1970: 1),
      suggestedFilename: "a.pdf")
    #expect(store.read(Self.key(), freshAgainst: nil) == nil)

    let (store2, _) = try Self.makeStore()
    let temp2 = try Self.writeTempFile(Data("x".utf8))
    try store2.store(
      Self.key(), movingFrom: temp2, modified: nil,
      suggestedFilename: "a.pdf")
    #expect(
      store2.read(Self.key(), freshAgainst: Date(timeIntervalSince1970: 1))
        == nil)
  }

  @Test
  func storeOverwriteReplacesAtomically() throws {
    let (store, _) = try Self.makeStore()
    let first = try Self.writeTempFile(Data("first".utf8))
    try store.store(
      Self.key(), movingFrom: first, modified: nil,
      suggestedFilename: "a.pdf")

    let second = try Self.writeTempFile(Data("second".utf8))
    let hit = try store.store(
      Self.key(), movingFrom: second, modified: nil,
      suggestedFilename: "a.pdf")
    #expect(try Data(contentsOf: hit.canonicalURL) == Data("second".utf8))
    #expect(try Data(contentsOf: hit.friendlyURL) == Data("second".utf8))
  }

  @Test
  func friendlyLinkRematerializesAfterPurge() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    let hit = try store.store(
      Self.key(), movingFrom: temp, modified: nil,
      suggestedFilename: "a.pdf")

    try FileManager.default.removeItem(at: hit.friendlyURL)
    #expect(!FileManager.default.fileExists(atPath: hit.friendlyURL.path))

    let again = store.read(Self.key(), freshAgainst: nil)
    #expect(again != nil)
    #expect(FileManager.default.fileExists(atPath: again!.friendlyURL.path))
    #expect(again?.friendlyURL.lastPathComponent == "a.pdf")
  }

  @Test
  func friendlyLinkSharesInodeWithCanonical() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("payload".utf8))
    let hit = try store.store(
      Self.key(), movingFrom: temp, modified: nil,
      suggestedFilename: "a.pdf")

    let canonAttr = try FileManager.default.attributesOfItem(
      atPath: hit.canonicalURL.path)
    let friendlyAttr = try FileManager.default.attributesOfItem(
      atPath: hit.friendlyURL.path)
    let canonInode = canonAttr[.systemFileNumber] as? NSNumber
    let friendlyInode = friendlyAttr[.systemFileNumber] as? NSNumber
    #expect(canonInode != nil)
    #expect(canonInode == friendlyInode)
  }

  @Test
  func friendlyNameCollisionGetsDisambiguated() throws {
    let (store, _) = try Self.makeStore()

    let temp1 = try Self.writeTempFile(Data("one".utf8))
    let hit1 = try store.store(
      Self.key(doc: 1), movingFrom: temp1, modified: nil,
      suggestedFilename: "same.pdf")

    let temp2 = try Self.writeTempFile(Data("two".utf8))
    let hit2 = try store.store(
      Self.key(doc: 2), movingFrom: temp2, modified: nil,
      suggestedFilename: "same.pdf")

    #expect(hit1.friendlyURL.lastPathComponent == "same.pdf")
    #expect(hit2.friendlyURL.lastPathComponent == "same (2).pdf")
    #expect(try Data(contentsOf: hit1.friendlyURL) == Data("one".utf8))
    #expect(try Data(contentsOf: hit2.friendlyURL) == Data("two".utf8))
  }

  @Test
  func sanitizesInvalidFilename() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    let hit = try store.store(
      Self.key(), movingFrom: temp, modified: nil,
      suggestedFilename: "evil/path\0with/slashes.pdf")
    #expect(!hit.friendlyURL.lastPathComponent.contains("/"))
    #expect(!hit.friendlyURL.lastPathComponent.contains("\0"))
  }

  @Test
  func emptyFilenameFallsBackToKindBased() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    let hit = try store.store(
      Self.key(), movingFrom: temp, modified: nil,
      suggestedFilename: "")
    #expect(hit.friendlyURL.lastPathComponent == "archive.pdf")
  }

  @Test
  func deleteRemovesBlobSidecarAndFriendly() throws {
    let (store, _) = try Self.makeStore()
    let temp = try Self.writeTempFile(Data("x".utf8))
    let hit = try store.store(
      Self.key(), movingFrom: temp, modified: nil,
      suggestedFilename: "a.pdf")

    try store.delete(Self.key())
    #expect(!FileManager.default.fileExists(atPath: hit.canonicalURL.path))
    #expect(!FileManager.default.fileExists(atPath: hit.friendlyURL.path))
    #expect(store.read(Self.key(), freshAgainst: nil) == nil)
  }
}
