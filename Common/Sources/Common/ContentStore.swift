//
//  ContentStore.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.05.26.
//

import Foundation
import os

private let log = Logger(
  subsystem: "com.paulgessinger.swift-paperless", category: "ContentStore")

/// On-disk blob cache keyed by `(serverID, documentRemoteID, versionID, kind)`.
///
/// Lives in the app-group container so the Share Extension (and a future
/// File Provider extension) can read it on a locked device. Files are written
/// with `.completeUntilFirstUserAuthentication` protection on iOS; on macOS
/// (host tests) the protection class is a no-op.
///
/// `Hit.friendlyURL` is a hardlink under `Caches/ContentStore/Friendly/`
/// named after the server-provided filename, so consumers like
/// `UIActivityViewController` show a recognizable name.
public struct ContentStore: Sendable {
  public enum Kind: String, Sendable, CaseIterable {
    case original
    case archive
    case thumbnail

    public var fileExtension: String {
      switch self {
      case .original, .archive: "pdf"
      case .thumbnail: "bin"
      }
    }
  }

  public struct Key: Hashable, Sendable {
    public let serverID: UUID
    public let documentRemoteID: UInt
    public let versionID: String
    public let kind: Kind

    public static let currentVersion = "current"

    public init(
      serverID: UUID, documentRemoteID: UInt,
      versionID: String = Key.currentVersion, kind: Kind
    ) {
      self.serverID = serverID
      self.documentRemoteID = documentRemoteID
      self.versionID = versionID
      self.kind = kind
    }
  }

  public struct Hit: Sendable {
    public let canonicalURL: URL
    public let friendlyURL: URL
    public let suggestedFilename: String
  }

  public enum StoreError: Error {
    case appGroupUnavailable(identifier: String)
  }

  public static let appGroup = "group.com.paulgessinger.swift-paperless"

  private let root: URL

  public init(appGroupIdentifier: String = ContentStore.appGroup) throws {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    else {
      throw StoreError.appGroupUnavailable(identifier: appGroupIdentifier)
    }
    try self.init(root: container)
  }

  // Test seam: cross-package consumers (e.g. NetworkingTests) construct a
  // ContentStore rooted at a temp directory rather than an app-group container.
  public init(root: URL) throws {
    self.root = root
    try createDirectory(canonicalRoot)
    try createDirectory(friendlyRoot)
  }

  // MARK: - Paths

  private var canonicalRoot: URL {
    root.appendingPathComponent("Caches/ContentStore", isDirectory: true)
  }

  private var friendlyRoot: URL {
    canonicalRoot.appendingPathComponent("Friendly", isDirectory: true)
  }

  private func directory(for key: Key) -> URL {
    canonicalRoot
      .appendingPathComponent(key.serverID.uuidString, isDirectory: true)
      .appendingPathComponent(String(key.documentRemoteID), isDirectory: true)
      .appendingPathComponent(key.versionID, isDirectory: true)
  }

  public func url(for key: Key) -> URL {
    directory(for: key).appendingPathComponent(
      "\(key.kind.rawValue).\(key.kind.fileExtension)")
  }

  private func sidecarURL(for key: Key) -> URL {
    directory(for: key).appendingPathComponent("\(key.kind.rawValue).meta.json")
  }

  // MARK: - Operations

  public func exists(_ key: Key) -> Bool {
    FileManager.default.fileExists(atPath: url(for: key).path)
  }

  public func read(_ key: Key, freshAgainst modified: Date?) -> Hit? {
    let canonical = url(for: key)
    guard FileManager.default.fileExists(atPath: canonical.path) else {
      return nil
    }
    guard let sidecar = readSidecar(for: key) else { return nil }
    guard staleness(sidecar.modified, matches: modified) else { return nil }

    let friendly =
      (try? materializeFriendlyLink(
        for: key,
        suggestedFilename: sidecar.suggestedFilename,
        canonical: canonical)) ?? canonical

    return Hit(
      canonicalURL: canonical,
      friendlyURL: friendly,
      suggestedFilename: sidecar.suggestedFilename)
  }

  @discardableResult
  public func store(
    _ key: Key,
    movingFrom tempURL: URL,
    modified: Date?,
    suggestedFilename: String
  ) throws -> Hit {
    let directory = directory(for: key)
    try createDirectory(directory)
    let canonical = url(for: key)

    // Capture old inode before overwriting so we can recognize stale friendly
    // links that still point at our previous blob and remove them. A friendly
    // link pointing at a *different* doc's blob is a collision (handled by
    // materializeFriendlyLink via disambiguation), not ours to clear.
    let oldCanonicalInode = inode(of: canonical)

    if FileManager.default.fileExists(atPath: canonical.path) {
      _ = try FileManager.default.replaceItemAt(canonical, withItemAt: tempURL)
    } else {
      try FileManager.default.moveItem(at: tempURL, to: canonical)
    }
    applyFileProtection(canonical)

    try writeSidecar(
      for: key, modified: modified, suggestedFilename: suggestedFilename)

    // Sweep any friendly link still pointing at the *previous* canonical
    // inode — covers both (i) plain overwrite under the same name and
    // (ii) a server-side rename where the old name's link would otherwise
    // be orphaned forever.
    if let oldCanonicalInode {
      removeFriendlyLinks(matchingInode: oldCanonicalInode)
    }

    let friendly =
      (try? materializeFriendlyLink(
        for: key,
        suggestedFilename: suggestedFilename,
        canonical: canonical)) ?? canonical

    return Hit(
      canonicalURL: canonical,
      friendlyURL: friendly,
      suggestedFilename: suggestedFilename)
  }

  private func inode(of url: URL) -> NSNumber? {
    guard
      let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
    else { return nil }
    return attr[.systemFileNumber] as? NSNumber
  }

  public func delete(_ key: Key) throws {
    let canonical = url(for: key)
    // Capture the inode before removing the blob so we can sweep every
    // friendly link that points at it — including disambiguated names
    // (`name (docID).ext`) that the sidecar's suggestedFilename alone
    // cannot tell us about.
    let canonicalInode = inode(of: canonical)

    try? FileManager.default.removeItem(at: canonical)
    try? FileManager.default.removeItem(at: sidecarURL(for: key))

    if let canonicalInode {
      removeFriendlyLinks(matchingInode: canonicalInode)
    }
  }

  /// Removes every entry under `Friendly/` whose underlying inode equals
  /// the given inode. Bounded by the size of `Friendly/`, which the OS
  /// keeps small under storage pressure. Best-effort: failures are swallowed.
  private func removeFriendlyLinks(matchingInode target: NSNumber) {
    guard
      let contents = try? FileManager.default.contentsOfDirectory(
        at: friendlyRoot, includingPropertiesForKeys: nil)
    else { return }
    for entry in contents where inode(of: entry) == target {
      try? FileManager.default.removeItem(at: entry)
    }
  }

  // MARK: - Sidecar

  private struct Sidecar: Codable {
    var modified: Date?
    var suggestedFilename: String
    var writtenAt: Date
  }

  private func writeSidecar(
    for key: Key, modified: Date?, suggestedFilename: String
  ) throws {
    let sidecar = Sidecar(
      modified: modified, suggestedFilename: suggestedFilename,
      writtenAt: Date())
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(sidecar)
    let url = sidecarURL(for: key)
    try data.write(to: url, options: .atomic)
    applyFileProtection(url)
  }

  private func readSidecar(for key: Key) -> Sidecar? {
    let url = sidecarURL(for: key)
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(Sidecar.self, from: data)
  }

  private func staleness(_ sidecar: Date?, matches arg: Date?) -> Bool {
    switch (sidecar, arg) {
    case (nil, nil): true
    case (let l?, let r?): l == r
    default: false
    }
  }

  // MARK: - Friendly link

  private func friendlyURL(for key: Key, suggestedFilename: String) -> URL {
    let sanitized = sanitize(filename: suggestedFilename, kind: key.kind)
    return friendlyRoot.appendingPathComponent(sanitized)
  }

  private func materializeFriendlyLink(
    for key: Key, suggestedFilename: String, canonical: URL
  ) throws -> URL {
    var friendly = friendlyURL(
      for: key, suggestedFilename: suggestedFilename)
    let manager = FileManager.default

    if manager.fileExists(atPath: friendly.path) {
      if sameInode(friendly, canonical) {
        return friendly
      }
      // Different inode at the friendly path means a *different* document
      // hashed to the same filename. Disambiguate by appending the doc ID.
      friendly = disambiguatedFriendlyURL(for: friendly, key: key)
      if manager.fileExists(atPath: friendly.path) {
        if sameInode(friendly, canonical) {
          return friendly
        }
        try? manager.removeItem(at: friendly)
      }
    }

    try manager.linkItem(at: canonical, to: friendly)
    return friendly
  }

  private func sameInode(_ a: URL, _ b: URL) -> Bool {
    guard let aI = inode(of: a), let bI = inode(of: b) else { return false }
    return aI == bI
  }

  private func disambiguatedFriendlyURL(for url: URL, key: Key) -> URL {
    let ext = url.pathExtension
    let base = url.deletingPathExtension().lastPathComponent
    let newName =
      ext.isEmpty
      ? "\(base) (\(key.documentRemoteID))"
      : "\(base) (\(key.documentRemoteID)).\(ext)"
    return url.deletingLastPathComponent().appendingPathComponent(newName)
  }

  private func sanitize(filename: String, kind: Kind) -> String {
    let invalid = CharacterSet(charactersIn: "/\0").union(.controlCharacters)
    let scrubbed =
      filename
      .components(separatedBy: invalid).joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if scrubbed.isEmpty {
      return "\(kind.rawValue).\(kind.fileExtension)"
    }
    return scrubbed
  }

  // MARK: - Filesystem helpers

  private func createDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: true)
    applyFileProtection(url)
  }

  private func applyFileProtection(_ url: URL) {
    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS) || targetEnvironment(macCatalyst)
      do {
        try FileManager.default.setAttributes(
          [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
          ofItemAtPath: url.path)
      } catch {
        log.debug(
          "Could not set file protection on \(url.path, privacy: .public): \(error)"
        )
      }
    #endif
  }
}
