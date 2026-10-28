//
//  ContentStore.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.05.26.
//

import CryptoKit
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
/// File Provider extension) can read it on a locked device, under Application
/// Support rather than Caches so iOS does not purge it, and excluded from
/// backups since everything in it comes from the server. Files are written
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
    /// The document's full OCR text, zlib-compressed.
    case content

    /// None for document files: their type isn't known from the key (a
    /// document without an archive version stores its original as `.archive`),
    /// so the name makes no claim. Whatever leaves the app goes through a
    /// named link instead.
    public var fileExtension: String? {
      switch self {
      case .original, .archive: nil
      case .thumbnail: "bin"
      case .content: "zlib"
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

  /// The container the store is laid out under, where the other caches live
  /// next to it (see ``AppGroup/Layout``).
  public let root: URL

  public init(appGroupIdentifier: String = AppGroup.identifier) throws {
    guard let container = AppGroup.container(identifier: appGroupIdentifier) else {
      throw StoreError.appGroupUnavailable(identifier: appGroupIdentifier)
    }
    try self.init(root: container)
  }

  // Test seam: cross-package consumers (e.g. NetworkingTests) construct a
  // ContentStore rooted at a temp directory rather than an app-group container.
  public init(root: URL) throws {
    self.root = root
    let legacy = AppGroup.Layout.legacyContentStore(in: root)
    if FileManager.default.fileExists(atPath: legacy.path),
      !FileManager.default.fileExists(atPath: canonicalRoot.path)
    {
      // Same volume: a rename, whatever the store holds.
      try createDirectory(canonicalRoot.deletingLastPathComponent())
      try FileManager.default.moveItem(at: legacy, to: canonicalRoot)
    }
    try createDirectory(canonicalRoot)
    dropLegacyExtensions()
    var excluded = canonicalRoot
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? excluded.setResourceValues(values)
  }

  // MARK: - Paths

  private var canonicalRoot: URL { AppGroup.Layout.contentStore(in: root) }

  private func directory(for key: Key) -> URL {
    canonicalRoot
      .appendingPathComponent(key.serverID.uuidString, isDirectory: true)
      .appendingPathComponent(String(key.versionID), isDirectory: true)
  }

  public func url(for key: Key) -> URL {
    let name = key.kind.fileExtension.map { "\(key.kind.rawValue).\($0)" } ?? key.kind.rawValue
    return directory(for: key).appendingPathComponent(name)
  }

  /// Present once the store holds no `.pdf` document names, so the walk below
  /// runs once rather than on every launch.
  private var extensionlessMarker: URL {
    canonicalRoot.appendingPathComponent(".extensionless")
  }

  /// Rename `archive.pdf` and `original.pdf` from builds that named every
  /// document file a PDF. A name left behind would be invisible to the
  /// inventory, and its bytes never reclaimed.
  private func dropLegacyExtensions() {
    guard !FileManager.default.fileExists(atPath: extensionlessMarker.path) else { return }
    var complete = true
    for serverDirectory in contents(of: canonicalRoot) {
      guard UUID(uuidString: serverDirectory.lastPathComponent) != nil else { continue }
      for versionDirectory in contents(of: serverDirectory) {
        for kind in [Kind.original, .archive] {
          let legacy = versionDirectory.appendingPathComponent("\(kind.rawValue).pdf")
          let current = versionDirectory.appendingPathComponent(kind.rawValue)
          guard FileManager.default.fileExists(atPath: legacy.path) else { continue }
          do {
            try FileManager.default.moveItem(at: legacy, to: current)
          } catch  where FileManager.default.fileExists(atPath: current.path) {
            // A download (possibly in another process) already put a file
            // under the new name, and that one is current.
            try? FileManager.default.removeItem(at: legacy)
          } catch {
            // Kept, and without the marker the next launch tries again.
            Logger.cache.error("Renaming \(legacy.path) failed: \(error)")
            complete = false
          }
        }
      }
    }
    guard complete else { return }
    FileManager.default.createFile(atPath: extensionlessMarker.path, contents: nil)
  }

  private func sidecarURL(for key: Key) -> URL {
    directory(for: key).appendingPathComponent("\(key.kind.rawValue).meta.json")
  }

  // MARK: - Operations

  public func exists(_ key: Key) -> Bool {
    FileManager.default.fileExists(atPath: url(for: key).path)
  }

  /// Move the downloaded file at `tempURL` into place, replacing what is
  /// there. Freshness is the file index's business, not the store's: the
  /// caller records the row once the file is in place.
  @discardableResult
  public func store(_ key: Key, movingFrom tempURL: URL) throws -> URL {
    let directory = directory(for: key)
    try createDirectory(directory)
    let canonical = url(for: key)

    if FileManager.default.fileExists(atPath: canonical.path) {
      _ = try FileManager.default.replaceItemAt(canonical, withItemAt: tempURL)
    } else {
      try FileManager.default.moveItem(at: tempURL, to: canonical)
    }
    applyFileProtection(canonical)
    return canonical
  }

  /// Write `data` as the blob for `key`: to a temporary name in the key's own
  /// directory first, then renamed into place, so the canonical name only ever
  /// holds a complete file. For small payloads that arrive in memory
  /// (thumbnails); downloads go through ``store(_:movingFrom:)``.
  @discardableResult
  public func storeData(_ data: Data, for key: Key) throws -> URL {
    let directory = directory(for: key)
    try createDirectory(directory)
    let temp = directory.appendingPathComponent(".\(key.kind.rawValue)-\(UUID().uuidString).tmp")
    try data.write(to: temp, options: .atomic)
    return try store(key, movingFrom: temp)
  }

  /// Write `text` as the blob for `key`, zlib-compressed. Returns the bytes
  /// the blob occupies, like ``size(of:)``.
  @discardableResult
  public func storeText(_ text: String, for key: Key) throws -> Int64 {
    let compressed = try (Data(text.utf8) as NSData).compressed(using: .zlib) as Data
    try storeData(compressed, for: key)
    return size(of: key) ?? Int64(compressed.count)
  }

  /// The text stored for `key` by ``storeText(_:for:)``, or `nil` when there
  /// is none.
  public func text(for key: Key) throws -> String? {
    guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
    let raw = try (data as NSData).decompressed(using: .zlib) as Data
    return String(decoding: raw, as: UTF8.self)
  }

  /// The checksum the index records for a text blob: SHA-256 of its UTF-8,
  /// so an unchanged text is recognized without reading the file.
  public static func checksum(of text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  /// Bytes the blob for `key` occupies on disk, or `nil` when there is none.
  /// Allocated size, like ``DiskUsage``, so the index sums to what deleting
  /// the files would free.
  public func size(of key: Key) -> Int64? {
    guard
      let values = try? url(for: key).resourceValues(forKeys: [
        .totalFileAllocatedSizeKey, .fileSizeKey,
      ])
    else { return nil }
    return (values.totalFileAllocatedSize ?? values.fileSize).map(Int64.init)
  }

  public func delete(_ key: Key) throws {
    try? FileManager.default.removeItem(at: url(for: key))
    try? FileManager.default.removeItem(at: sidecarURL(for: key))
  }

  /// Set the blob's modification date to `date`, for a caller about to record
  /// a new row over a file it kept: ``delete(_:ifNotModifiedAfter:)`` then
  /// treats it like a file the new row's download wrote. Throws when there is
  /// no blob at `key`.
  public func touch(_ key: Key, at date: Date) throws {
    try FileManager.default.setAttributes(
      [.modificationDate: date], ofItemAtPath: url(for: key).path)
  }

  /// A modification date set from a `Date` can read back up to ~100 ns later,
  /// since `Date` and the file system's timespec round differently; a touched
  /// file must still count as not modified after the date it was touched to.
  private static let modificationDateTolerance: TimeInterval = 0.000_001

  /// Remove the blob for `key` unless it was written after `date`, and return
  /// the bytes it held; `nil` when it was newer or absent.
  ///
  /// For a sweep that has claimed the file's index row: a download that
  /// replaced the file since the row was recorded has a newer modification
  /// date (files arrive by rename, which keeps the date they were written
  /// with, and the row is recorded after), and is that download's to keep.
  @discardableResult
  public func delete(_ key: Key, ifNotModifiedAfter date: Date) -> Int64? {
    let canonical = url(for: key)
    guard
      let values = try? canonical.resourceValues(forKeys: [
        .contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey,
      ]),
      let modified = values.contentModificationDate,
      modified <= date.addingTimeInterval(Self.modificationDateTolerance),
      (try? FileManager.default.removeItem(at: canonical)) != nil
    else { return nil }
    try? FileManager.default.removeItem(at: sidecarURL(for: key))
    return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
  }

  /// Remove every cached blob (all servers, all kinds) by tearing down the
  /// store root, then recreate the empty directory. Used by the debug
  /// "clear local storage" action.
  public func purge() throws {
    // Propagate a failed removal rather than swallowing it: recreating the
    // directory succeeds trivially when it is still there, so a `try?` here
    // would report a clean wipe while every blob was still on disk — and the
    // caller tells the user the cache is cleared.
    do {
      try FileManager.default.removeItem(at: canonicalRoot)
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
    {
      // Nothing cached yet; an absent root is already the desired end state.
    }
    try createDirectory(canonicalRoot)
  }

  // MARK: - Inventory

  /// One blob found on disk, for the repair walk that matches the directory
  /// against the file index.
  public struct InventoryEntry: Sendable, Equatable {
    public let key: Key
    public let size: Int64
    /// Newest modification anywhere in the version's directory, the directory
    /// itself included: the grace-window input, as for the reclaim.
    public let youngestModification: Date?
    /// A sidecar from a build that recorded freshness next to the file.
    public let hasLegacySidecar: Bool
  }

  /// Every blob under the store root with one of this store's own names. Other
  /// entries are not this store's to judge and are skipped.
  public func inventory() -> [InventoryEntry] {
    var entries: [InventoryEntry] = []
    for serverDirectory in contents(of: canonicalRoot) {
      guard let serverID = UUID(uuidString: serverDirectory.lastPathComponent) else { continue }
      for versionDirectory in contents(of: serverDirectory) {
        guard let versionID = UInt(versionDirectory.lastPathComponent) else { continue }
        let youngest = youngestModification(in: versionDirectory)
        for kind in Kind.allCases {
          let key = Key(serverID: serverID, versionID: versionID, kind: kind)
          guard let size = size(of: key) else { continue }
          entries.append(
            InventoryEntry(
              key: key, size: size, youngestModification: youngest,
              hasLegacySidecar: FileManager.default.fileExists(atPath: sidecarURL(for: key).path)))
        }
      }
    }
    return entries
  }

  /// The UUIDs of the server directories under the store root, a removed
  /// server's leftovers included.
  public func serverDirectories() -> Set<UUID> {
    Set(contents(of: canonicalRoot).compactMap { UUID(uuidString: $0.lastPathComponent) })
  }

  /// Drop every version and server directory that is empty. `rmdir(2)` fails
  /// atomically on a directory something was just written into, so a blob
  /// another process is adding survives.
  public func removeEmptyDirectories() {
    for serverDirectory in contents(of: canonicalRoot) {
      guard UUID(uuidString: serverDirectory.lastPathComponent) != nil else { continue }
      for versionDirectory in contents(of: serverDirectory) {
        removeIfEmpty(versionDirectory)
      }
      removeIfEmpty(serverDirectory)
    }
  }

  // MARK: - Directory helpers

  private func contents(of directory: URL) -> [URL] {
    // No `.skipsHiddenFiles`: this listing also feeds the grace-window check,
    // which has to see *everything* a concurrent writer may have just put there.
    (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]))
      ?? []
  }

  /// Newest modification time anywhere in `directory`, the directory itself
  /// included — a rename into it (a download landing, a sidecar being replaced)
  /// bumps the directory even when the file it created is one this store would
  /// not recognise by name.
  private func youngestModification(in directory: URL) -> Date? {
    var newest = modificationDate(of: directory)
    for entry in contents(of: directory) {
      guard let date = modificationDate(of: entry) else { continue }
      newest = max(newest ?? .distantPast, date)
    }
    return newest
  }

  private func modificationDate(of url: URL) -> Date? {
    try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
  }

  /// Drop a directory the sweep emptied.
  ///
  /// `rmdir(2)` rather than `FileManager.removeItem`: it fails atomically with
  /// `ENOTEMPTY` instead of deleting a subtree, so a blob another process wrote
  /// between the listing above and this call survives. Failing is the expected
  /// case (the directory is still in use) and says nothing worth logging.
  private func removeIfEmpty(_ directory: URL) {
    _ = rmdir(directory.path)
  }

  // MARK: - Sidecar

  /// What builds before the file index wrote next to each blob. Read once by
  /// the repair walk to adopt such a file, then removed.
  public struct LegacySidecar: Codable, Sendable, Equatable {
    public var modified: Date?
    public var writtenAt: Date

    public init(modified: Date?, writtenAt: Date) {
      self.modified = modified
      self.writtenAt = writtenAt
    }
  }

  private typealias Sidecar = LegacySidecar

  public func readLegacySidecar(for key: Key) -> LegacySidecar? {
    readSidecar(for: key)
  }

  public func removeLegacySidecar(for key: Key) {
    try? FileManager.default.removeItem(at: sidecarURL(for: key))
  }

  private func readSidecar(for key: Key) -> Sidecar? {
    let url = sidecarURL(for: key)
    guard let data = try? Data(contentsOf: url) else { return nil }
    // Matches writeSidecar's numeric date encoding (JSONDecoder's default).
    return try? JSONDecoder().decode(Sidecar.self, from: data)
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
