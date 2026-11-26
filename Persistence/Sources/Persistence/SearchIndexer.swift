//
//  SearchIndexer.swift
//  Persistence
//
//  Keeps the full-text index (`Database+SearchIndex`) in step with the texts
//  the `ContentStore` holds.
//

import Common
import Foundation
import os

/// Reads the stored document texts the full-text index is behind on and
/// indexes them.
///
/// One per process, like ``ContentReclaimer``: the store and the index are
/// shared by every server. It is driven by the file index rather than by the
/// code that stores a text (a document being opened, the content fill, a kept
/// document's download): ``follow()`` runs a pass whenever a file is recorded
/// or removed, so every one of those paths is covered, as are texts stored
/// before the index existed. Removal is not its job; the triggers on `file`
/// drop an entry with its row.
public actor SearchIndexer {
  /// What one pass did.
  public struct Report: Sendable, Equatable {
    /// Texts written to the index.
    public var indexed = 0
    /// Candidates whose file could not be read; they are tried again by the
    /// next pass, and the reclaimer's repair drops a row that has no file.
    public var unreadable = 0

    public init(indexed: Int = 0, unreadable: Int = 0) {
      self.indexed = indexed
      self.unreadable = unreadable
    }
  }

  /// How much one transaction indexes. Small enough that a list on screen
  /// isn't kept waiting for the writer, large enough that a library's backlog
  /// goes through in a few hundred of them.
  enum Batch {
    static let candidates = 64
    /// Characters of text held in memory at once.
    static let characters = 2_000_000
    /// A pass that indexed at least this many texts merges the index's
    /// segments afterwards. Only a backlog gets there (the first pass after
    /// the index was introduced, or after the cache was cleared); the passes
    /// that follow a download are small, and FTS5 merges those as it goes.
    static let optimizeAfter = 2_000
  }

  private let database: Database
  private let store: ContentStore?

  private var current: Task<Report, Never>?
  private var rerunRequested = false
  private var following: Task<Void, Never>?

  public init(database: Database, store: ContentStore?) {
    self.database = database
    self.store = store
  }

  /// Index what is awaiting, or join the pass in flight and have another
  /// follow it: that one may have read its candidates before the caller's
  /// text was stored.
  @discardableResult
  public func run() async -> Report {
    if let current {
      rerunRequested = true
      return await current.value
    }
    let task = Task { await pass() }
    current = task
    var report = await task.value
    current = nil
    if rerunRequested {
      rerunRequested = false
      let next = await run()
      report.indexed += next.indexed
      report.unreadable = next.unreadable
    }
    return report
  }

  /// Run a pass now and after every change to the file index, until
  /// ``stop()``. `perform` wraps each pass, for a caller that has to keep the
  /// database open while one runs.
  ///
  /// The stream buffers only its newest change, and a pass indexes everything
  /// awaiting, so a burst of downloads costs one pass, not one each.
  public func follow(
    perform: @escaping @Sendable (@Sendable () async -> Void) async -> Void = { await $0() }
  ) {
    guard following == nil else { return }
    let changes = database.observeFileIndexChanges()
    following = Task { [weak self] in
      do {
        for try await _ in changes {
          guard let self else { return }
          await perform { await self.run() }
          // A download in progress records files continuously; let a few
          // gather rather than start a pass for each.
          try await Task.sleep(for: .seconds(1))
        }
      } catch is CancellationError {
      } catch {
        Logger.persistence.error("Search indexer stopped following the file index: \(error)")
      }
    }
  }

  public func stop() {
    following?.cancel()
    following = nil
  }

  private func pass() async -> Report {
    var report = Report()
    guard let store else { return report }
    var cursor: Double?
    do {
      while !Task.isCancelled {
        let candidates = try await database.contentAwaitingIndex(
          limit: Batch.candidates, storedBefore: cursor)
        guard let last = candidates.last else { break }
        cursor = last.storedAt

        var texts: [(candidate: ContentIndexCandidate, text: String)] = []
        var characters = 0
        for candidate in candidates {
          guard let text = try? store.text(for: candidate.key) else {
            report.unreadable += 1
            continue
          }
          texts.append((candidate, text))
          characters += text.utf8.count
          if characters >= Batch.characters {
            report.indexed += try await database.indexContent(texts)
            texts.removeAll()
            characters = 0
          }
        }
        report.indexed += try await database.indexContent(texts)
        await Task.yield()
      }
    } catch is CancellationError {
    } catch {
      // The texts stay awaiting, so the next pass takes them up again.
      Logger.persistence.error("Search indexing stopped: \(error)")
    }
    if report.indexed > 0 {
      Logger.persistence.info(
        "Search index: indexed \(report.indexed, privacy: .public) text(s), \(report.unreadable, privacy: .public) unreadable"
      )
      if report.indexed >= Batch.optimizeAfter {
        try? await database.optimizeSearchIndex()
      }
    }
    return report
  }
}
