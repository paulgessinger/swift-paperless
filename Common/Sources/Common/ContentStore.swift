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

  // MARK: - Reclamation

  /// Files younger than this are never reclaimed, whatever the database says
  /// about them.
  ///
  /// A blob and the `document` row that makes it reachable are written by two
  /// different subsystems — and, with the Share Extension, two different
  /// processes — with no transaction spanning both. A download therefore exists
  /// on disk for a short window before the row that references it, and the app
  /// group is shared, so the other process may be mid-write while this one
  /// sweeps. An hour is orders of magnitude longer than that window and still
  /// nothing against the lifetime of a superseded version.
  public static let reclaimGracePeriod: TimeInterval = 3600

  /// What one ``reclaim(retaining:gracePeriod:now:)`` pass did.
  public struct ReclaimReport: Sendable, Equatable {
    /// Blobs and sidecars actually unlinked.
    public var removedFiles = 0
    /// Bytes those files occupied, as reported just before the unlink.
    public var reclaimedBytes: Int64 = 0
    /// Unreferenced versions left in place because something in their directory
    /// was written inside the grace window.
    public var keptRecent = 0
    /// Version directories looked at, referenced ones included.
    public var examinedVersions = 0

    public init() {}
  }

  /// Delete every stored blob no live document version points at.
  ///
  /// Reachability, not reference counting: the database already knows exactly
  /// which version each cached document is at, so one query answers the whole
  /// question — whereas a refcount would have to be kept in step across two
  /// processes and would drift the moment either was killed mid-update.
  ///
  /// - Parameter retaining: the **complete** `server → live version ids` map,
  ///   across every server, read from the database in one pass. Anything absent
  ///   from it is unreachable: a superseded version, a document deleted on the
  ///   server, or a whole server whose connection was removed (its cache rows
  ///   cascade away with it). A map narrowed to one server would delete every
  ///   other server's live blobs, so callers must not narrow it.
  /// - Parameter now: injectable clock, so tests can age files without having
  ///   to backdate them.
  ///
  /// Non-throwing on purpose: every failure mode here is per-file (a directory
  /// that vanished, a file another process removed first) and the response to
  /// each is to skip it and carry on, not to abandon the sweep.
  public func reclaim(
    retaining: [UUID: Set<UInt>],
    gracePeriod: TimeInterval = ContentStore.reclaimGracePeriod,
    now: Date = Date()
  ) -> ReclaimReport {
    var report = ReclaimReport()

    for serverDirectory in contents(of: canonicalRoot) {
      // Anything whose name isn't one of our own path components was not
      // written by this store; leave it alone rather than guess at it.
      guard let serverID = UUID(uuidString: serverDirectory.lastPathComponent) else { continue }
      let retainedVersions = retaining[serverID] ?? []

      for versionDirectory in contents(of: serverDirectory) {
        guard let versionID = UInt(versionDirectory.lastPathComponent) else { continue }
        report.examinedVersions += 1
        if retainedVersions.contains(versionID) { continue }

        if let youngest = youngestModification(in: versionDirectory),
          now.timeIntervalSince(youngest) < gracePeriod
        {
          report.keptRecent += 1
          continue
        }

        // Only the names this store itself writes are candidates, so a
        // temporary or partial file a concurrent writer left behind is never
        // touched — the canonical blobs arrive by rename and are complete the
        // moment they appear under these names.
        for kind in Kind.allCases {
          let key = Key(serverID: serverID, versionID: versionID, kind: kind)
          for file in [url(for: key), sidecarURL(for: key)] {
            guard let bytes = removeIfPresent(file) else { continue }
            report.removedFiles += 1
            report.reclaimedBytes += bytes
          }
        }

        removeIfEmpty(versionDirectory)
      }

      removeIfEmpty(serverDirectory)
    }

    Logger.cache.info(
      "ContentStore reclaim removed \(report.removedFiles, privacy: .public) files (\(report.reclaimedBytes, privacy: .public) bytes) across \(report.examinedVersions, privacy: .public) versions, kept \(report.keptRecent, privacy: .public) recent"
    )
    return report
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

  /// Unlink `url`, returning the bytes it held, or nil when there was nothing
  /// to remove. Tolerates the file disappearing between the listing and here —
  /// another process pruning the same blob, or a `purge()` racing this sweep —
  /// because the end state is the one we wanted either way.
  private func removeIfPresent(_ url: URL) -> Int64? {
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
    do {
      try FileManager.default.removeItem(at: url)
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
    {
      return nil
    } catch {
      Logger.cache.debug(
        "ContentStore reclaim could not remove \(url.path, privacy: .public): \(error)")
      return nil
    }
    return Int64(size ?? 0)
  }

  /// Drop a directory that reclamation emptied.
  ///
  /// `rmdir(2)` rather than `FileManager.removeItem`: it fails atomically with
  /// `ENOTEMPTY` instead of deleting a subtree, so a blob another process wrote
  /// between the listing above and this call survives. Failing is the expected
  /// case (the directory is still in use) and says nothing worth logging.
  private func removeIfEmpty(_ directory: URL) {
    _ = rmdir(directory.path)
  }

  // MARK: - Sidecar

  private struct Sidecar: Codable {
    var modified: Date?
    var writtenAt: Date
  }

  private func writeSidecar(for key: Key, modified: Date?) throws {
    let sidecar = Sidecar(modified: modified, writtenAt: Date())
    let encoder = JSONEncoder()
    // Encode dates as numeric time intervals (JSONEncoder's default strategy),
    // NOT ISO-8601: `.iso8601` truncates to whole seconds, but paperless
    // `modified` timestamps carry sub-second precision. A truncated sidecar
    // would never equal the live `document.modified`, so `read(_:freshAgainst:)`
    // would miss on every lookup and the cache would never serve a hit. A
    // numeric interval round-trips exactly.
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(sidecar)
    let url = sidecarURL(for: key)
    try data.write(to: url, options: .atomic)
    applyFileProtection(url)
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
