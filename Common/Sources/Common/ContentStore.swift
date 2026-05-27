//
//  ContentStore.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.05.26.
//

import Foundation
import os

/// On-disk blob cache keyed by `(serverID, versionID, kind)`.
///
/// `versionID` is the server-side document version row id; since paperless-ngx
/// stores versions as sibling rows in the document table, version ids share a
/// namespace with document ids, so a single id uniquely identifies the
/// content. For documents without a `versions` array (older backends, or
/// single-file docs) callers pass the document id directly — it equals the
/// root version id server-side.
///
/// Lives in the app-group container so the Share Extension (and a future
/// File Provider extension) can read it on a locked device. Files are written
/// with `.completeUntilFirstUserAuthentication` protection on iOS; on macOS
/// (host tests) the protection class is a no-op.
///
/// Returns canonical paths only; consumers that need to show the user a
/// recognizable filename (e.g. the share sheet) use a separate display name
/// from `Document.archivedFileName` / `Document.originalFileName` and pass it
/// to `UIActivityViewController` via `NSItemProvider.suggestedName`.
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
    public let versionID: UInt
    public let kind: Kind

    public init(serverID: UUID, versionID: UInt, kind: Kind) {
      self.serverID = serverID
      self.versionID = versionID
      self.kind = kind
    }
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
  }

  // MARK: - Paths

  private var canonicalRoot: URL {
    root.appendingPathComponent("Caches/ContentStore", isDirectory: true)
  }

  private func directory(for key: Key) -> URL {
    canonicalRoot
      .appendingPathComponent(key.serverID.uuidString, isDirectory: true)
      .appendingPathComponent(String(key.versionID), isDirectory: true)
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

  /// Returns the canonical URL if the blob exists, the sidecar is present,
  /// and the sidecar's `modified` equals the passed value.
  ///
  /// A nil `modified` (either side) is treated as "no staleness signal" and
  /// returns nil — the cache will not serve a hit without a positive
  /// validity check. Callers that genuinely have no timestamp should bypass
  /// the cache entirely rather than calling `read` with nil.
  public func read(_ key: Key, freshAgainst modified: Date?) -> URL? {
    guard let modified else { return nil }
    let canonical = url(for: key)
    guard FileManager.default.fileExists(atPath: canonical.path),
      let sidecar = readSidecar(for: key),
      sidecar.modified == modified
    else { return nil }
    return canonical
  }

  @discardableResult
  public func store(
    _ key: Key, movingFrom tempURL: URL, modified: Date?
  ) throws -> URL {
    let directory = directory(for: key)
    try createDirectory(directory)
    let canonical = url(for: key)

    if FileManager.default.fileExists(atPath: canonical.path) {
      _ = try FileManager.default.replaceItemAt(canonical, withItemAt: tempURL)
    } else {
      try FileManager.default.moveItem(at: tempURL, to: canonical)
    }
    applyFileProtection(canonical)

    try writeSidecar(for: key, modified: modified)
    return canonical
  }

  public func delete(_ key: Key) throws {
    try? FileManager.default.removeItem(at: url(for: key))
    try? FileManager.default.removeItem(at: sidecarURL(for: key))
  }

  // MARK: - Sidecar

  private struct Sidecar: Codable {
    var modified: Date?
    var writtenAt: Date
  }

  private func writeSidecar(for key: Key, modified: Date?) throws {
    let sidecar = Sidecar(modified: modified, writtenAt: Date())
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
        Logger.cache.debug(
          "Could not set file protection on \(url.path, privacy: .public): \(error)"
        )
      }
    #endif
  }
}
