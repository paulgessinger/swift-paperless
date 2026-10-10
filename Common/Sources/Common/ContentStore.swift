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

  public static let appGroup = AppGroup.identifier

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

  // MARK: - Grace

  /// A file without an index row is left alone while anything in its version
  /// directory is younger than this.
  ///
  /// A blob and its row are written by two different subsystems — and, with
  /// the Share Extension, two different processes — with no transaction
  /// spanning both. A download therefore exists on disk for a short window
  /// before the row that records it, and the app group is shared, so the other
  /// process may be mid-write while this one sweeps. An hour is orders of
  /// magnitude longer than that window.
  public static let reclaimGracePeriod: TimeInterval = 3600

  // MARK: - Usage

  /// Disk taken by the store, as a whole and per server.
  public struct Usage: Sendable, Equatable {
    /// Everything under the store root, including anything not filed under a
    /// server (so the total never hides space the per-server rows can't place).
    public var total: DiskUsage = .zero
    public var byServer: [UUID: DiskUsage] = [:]

    public init(total: DiskUsage = .zero, byServer: [UUID: DiskUsage] = [:]) {
      self.total = total
      self.byServer = byServer
    }
  }

  /// Measure the store with a full directory walk — slow for a large store, so
  /// call it off the main actor.
  ///
  /// Per-server figures come straight from the layout: every blob lives under
  /// its server's directory, so attributing it costs nothing beyond the walk
  /// that the total needs anyway, and doesn't need the database at all.
  ///
  /// ``DiskUsage/files`` counts blobs only. The metadata sidecar next to each
  /// one still adds to the bytes, but counting it would double the number of
  /// downloads the user is told about.
  public func usage() -> Usage {
    var usage = Usage()
    for entry in contents(of: canonicalRoot) {
      let measured = DiskUsage.measure(entry, counting: Self.isBlob)
      usage.total += measured
      if let serverID = UUID(uuidString: entry.lastPathComponent) {
        usage.byServer[serverID, default: .zero] += measured
      }
    }
    return usage
  }

  private static let blobNames = Set(
    Kind.allCases.map { "\($0.rawValue).\($0.fileExtension)" })

  private static func isBlob(_ url: URL) -> Bool {
    blobNames.contains(url.lastPathComponent)
  }

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
