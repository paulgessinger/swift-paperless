//
//  ContentReclaimer.swift
//  Persistence
//
//  The process-wide owner of the cached files: the `FileIndex` the download
//  path records into, the storage budget, and the sweep that keeps the
//  `ContentStore` directory and the `file` table in step.
//

import Common
import Foundation
import os

/// Keeps the `ContentStore` and its index in step, and the budgeted files under
/// the budget.
///
/// One per process, held by the app stack: the store is a single app-group
/// directory shared by every server, and the reachable set is one query over
/// every server's documents, so a per-server sweep could not tell a removed
/// server's leftovers from another server's live files.
///
/// A pass runs three phases. *Unreferenced*: rows whose version no cached
/// document is at any more lose their file and their row. *Eviction*: the
/// evictable files are removed least recently accessed first until what is
/// left fits the budget. *Repair*: the directory is matched against the
/// index, so a file without a row is adopted (when a build from before the
/// index left its sidecar) or removed, and a row without a file is dropped.
/// Files always go before rows: a row without a file is repaired on the next
/// pass, a file without a row would sit unaccounted for.
public actor ContentReclaimer: FileIndex {
  /// What the evictable files may take, in total across servers.
  public static let budgetBytes: Int64 = 500_000_000
  /// A file accessed inside this window is never evicted, so a pass does not
  /// unlink a file that is on screen.
  public static let recentAccessGrace: TimeInterval = 300
  /// How often ``runIfDue(reason:)`` lets a pass run.
  public static let dueInterval: TimeInterval = 3600
  /// Accesses to one file inside this window are recorded once.
  static let accessCoalescing: TimeInterval = 60

  public enum Reason: String, Sendable {
    case launch
    case connectionRemoved
    case overBudget
    case afterReconcile
    case manual
  }

  /// What one pass did.
  public struct Report: Sendable, Equatable {
    public var reason: Reason
    /// Rows whose version no cached document is at, dropped with their files.
    public var unreferencedRows = 0
    public var unreferencedBytes: Int64 = 0
    /// Files removed for the budget.
    public var evictedFiles = 0
    public var evictedBytes: Int64 = 0
    /// Whether the repair walk ran; an over-budget pass skips it.
    public var walked = false
    /// Files from before the index entered into it.
    public var adoptedFiles = 0
    /// Files with no row, removed.
    public var orphanFiles = 0
    public var orphanBytes: Int64 = 0
    /// Rows with no file, removed.
    public var orphanRows = 0
    /// Files with no row left alone because they were written too recently.
    public var keptRecent = 0
    /// What the evictable files take after the pass.
    public var evictableBytes: Int64 = 0

    public var removedFiles: Int { unreferencedRows + evictedFiles + orphanFiles }
    public var removedBytes: Int64 { unreferencedBytes + evictedBytes + orphanBytes }

    public init(reason: Reason) {
      self.reason = reason
    }
  }

  /// The store the files live in, or `nil` when there is none to open; then
  /// the index is written but nothing is ever unlinked.
  public nonisolated let store: ContentStore?

  private let database: Database
  private let budget: Int64
  private let now: @Sendable () -> Date

  private var current: Task<Report, Never>?
  /// Set when a run was asked for while one was in flight: that pass may have
  /// read its input before the request, so another follows.
  private var rerunRequested = false
  private var lastRun: Date?
  private var lastTouched: [ContentStore.Key: Date] = [:]

  /// - Parameter now: injectable clock, so tests can age files and accesses
  ///   without backdating them.
  public init(
    database: Database, store: ContentStore?, budget: Int64 = ContentReclaimer.budgetBytes,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.database = database
    self.store = store
    self.budget = budget
    self.now = now
  }

  // MARK: - Running

  /// Run a pass, or join the one in flight and have another follow it.
  @discardableResult
  public func run(reason: Reason) async -> Report {
    if let current {
      rerunRequested = true
      return await current.value
    }
    let task = Task { await pass(reason) }
    current = task
    let report = await task.value
    current = nil
    if rerunRequested {
      rerunRequested = false
      return await run(reason: reason)
    }
    return report
  }

  /// Run a pass if none has run for ``dueInterval``; `nil` otherwise.
  @discardableResult
  public func runIfDue(reason: Reason) async -> Report? {
    if let lastRun, now().timeIntervalSince(lastRun) < Self.dueInterval {
      return nil
    }
    return await run(reason: reason)
  }

  private func pass(_ reason: Reason) async -> Report {
    var report = Report(reason: reason)
    let now = now()
    lastRun = now

    do {
      let unreferenced = try await database.unreferencedFiles()
      for row in unreferenced {
        report.unreferencedBytes += unlink(row.key)
      }
      report.unreferencedRows = try await database.deleteFiles(unreferenced)
    } catch {
      Logger.persistence.error("Content reclaim: dropping unreferenced files failed: \(error)")
    }

    // Without a store nothing can be unlinked, so neither phase below has
    // anything to do.
    if let store {
      do {
        let candidates = try await database.evictionCandidates(
          budget: budget, protectAccessedAfter: now.addingTimeInterval(-Self.recentAccessGrace))
        for row in candidates {
          report.evictedBytes += unlink(row.key)
          report.evictedFiles += 1
        }
        _ = try await database.deleteFiles(candidates)
      } catch {
        Logger.persistence.error("Content reclaim: eviction failed: \(error)")
      }

      if reason != .overBudget {
        do {
          try await repair(store, now: now, report: &report)
        } catch {
          Logger.persistence.error("Content reclaim: repair walk failed: \(error)")
        }
      }
    }

    report.evictableBytes = (try? await database.evictableFileBytes()) ?? 0
    Logger.persistence.info(
      "Content reclaim (\(reason.rawValue, privacy: .public)) removed \(report.removedFiles, privacy: .public) files (\(report.removedBytes, privacy: .public) bytes): \(report.unreferencedRows, privacy: .public) unreferenced, \(report.evictedFiles, privacy: .public) evicted, \(report.orphanFiles, privacy: .public) orphans; adopted \(report.adoptedFiles, privacy: .public), dropped \(report.orphanRows, privacy: .public) rows, kept \(report.keptRecent, privacy: .public) recent; \(report.evictableBytes, privacy: .public) evictable bytes left"
    )
    return report
  }

  /// Match the directory against the index.
  private func repair(_ store: ContentStore, now: Date, report: inout Report) async throws {
    report.walked = true
    let indexed = try await database.allFileKeys()
    let servers = Set(try database.allConnections().map(\.id))
    var present: Set<ContentStore.Key> = []
    var adoptions: [FileAdoption] = []

    for entry in store.inventory() {
      present.insert(entry.key)
      if indexed.contains(entry.key) {
        // The row is the record now; a sidecar left over is just a file.
        if entry.hasLegacySidecar { store.removeLegacySidecar(for: entry.key) }
        continue
      }
      guard servers.contains(entry.key.serverID) else {
        // Nothing can be mid-write for a server that no longer exists.
        report.orphanBytes += unlink(entry.key)
        report.orphanFiles += 1
        continue
      }
      if entry.hasLegacySidecar, let sidecar = store.readLegacySidecar(for: entry.key) {
        adoptions.append(
          FileAdoption(
            key: entry.key, size: entry.size, modified: sidecar.modified,
            storedAt: sidecar.writtenAt,
            lastAccessedAt: Self.isEvictable(entry.key.kind) ? sidecar.writtenAt : nil))
        continue
      }
      // No row and no record of what it is. A download lands on disk before
      // its row is written, possibly from the other process, so only an aged
      // file is an orphan.
      if let youngest = entry.youngestModification,
        now.timeIntervalSince(youngest) < ContentStore.reclaimGracePeriod
      {
        report.keptRecent += 1
      } else {
        report.orphanBytes += unlink(entry.key)
        report.orphanFiles += 1
      }
    }

    if !adoptions.isEmpty {
      let unresolved = Set(try await database.adoptFiles(adoptions))
      for adoption in adoptions {
        store.removeLegacySidecar(for: adoption.key)
        if unresolved.contains(adoption.key) {
          report.orphanBytes += unlink(adoption.key)
          report.orphanFiles += 1
        } else {
          report.adoptedFiles += 1
        }
      }
    }

    for key in indexed.subtracting(present) {
      try await database.deleteFile(key)
      report.orphanRows += 1
    }

    store.removeEmptyDirectories()
  }

  /// Remove the file for `key`; returns the bytes it held.
  private func unlink(_ key: ContentStore.Key?) -> Int64 {
    guard let key, let store else { return 0 }
    let size = store.size(of: key) ?? 0
    try? store.delete(key)
    return size
  }

  private static func isEvictable(_ kind: ContentStore.Kind) -> Bool {
    FileRecord.evictableKinds.contains(kind.rawValue)
  }

  // MARK: - FileIndex

  public func isFresh(_ key: ContentStore.Key, modified: Date) async throws -> Bool {
    try await database.freshFile(key, modified: modified) != nil
  }

  /// Records the row and, when the evictable total has gone over the budget,
  /// starts a pass to bring it back under.
  public func recordStore(
    _ key: ContentStore.Key, documentID: UInt, size: Int64, modified: Date?, checksum: String?,
    storedAt: Date
  ) async throws {
    let evictable = Self.isEvictable(key.kind)
    let total = try await database.recordFile(
      key, documentID: documentID, size: size, modified: modified, checksum: checksum,
      storedAt: storedAt, lastAccessedAt: evictable ? storedAt : nil)
    if evictable, total > budget {
      Task { await run(reason: .overBudget) }
    }
  }

  public func recordAccess(_ key: ContentStore.Key, at date: Date) async throws {
    if let last = lastTouched[key], date.timeIntervalSince(last) < Self.accessCoalescing {
      return
    }
    lastTouched[key] = date
    try await database.touchFile(key, at: date)
  }

  public func forget(_ key: ContentStore.Key) async throws {
    try await database.deleteFile(key)
  }
}
