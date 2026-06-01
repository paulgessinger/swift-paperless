//
//  DocumentListViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 14.05.2024.
//

import AppShared
import DataModel
import Foundation
import Networking
import Nuke
import Observation
import Persistence
import SwiftUI
import os

/// Drives the document list as a **source-of-truth observer**: `documents` is
/// assigned from a GRDB `observeDocumentPrefix` live query, never a network
/// fetch. The network's only job is to *fill* the cache (`fillDocumentQuery`).
///
/// The observed window is a **growing prefix** `[0, prefixLimit)` (offset 0, only
/// `prefixLimit` grows). Scrolling near the end bumps `prefixLimit` in coarse
/// steps and re-subscribes; scrolling back is free (the rows are already inside
/// the prefix). This needs only the forgiving "near the bottom" heuristic — no
/// precise visible-set tracking — so it tolerates SwiftUI's unreliable cell
/// lifecycle the same way the old append-only paging did.
@MainActor
@Observable
class DocumentListViewModel {
  private var store: DocumentStore
  private var filterState: FilterState
  private var errorController: ErrorController

  /// Assigned by the document observation; never a network fetch.
  var documents: [Document] = []
  var ready = false
  var noPermissions = false

  /// Server-reported total (scrollbar extent), from the query-status observation.
  var totalCount: UInt?

  /// True while a fill (page-1 await) or refresh is in flight.
  private(set) var isFetching = false

  // Growing-prefix state.
  @ObservationIgnored private var queryKey: QueryKey?
  @ObservationIgnored private var prefixLimit: Int
  @ObservationIgnored private nonisolated(unsafe) var fill: QueryFillHandle?
  @ObservationIgnored private nonisolated(unsafe) var documentTask: Task<Void, Never>?
  @ObservationIgnored private nonisolated(unsafe) var statusTask: Task<Void, Never>?

  private let initialLimit = 250
  private let widenStep = 250
  private let fetchMargin = 25

  @ObservationIgnored private var prefetchedIds: Set<UInt> = []
  private var imagePrefetcher: ImagePrefetcher
  private var prefetchPipeline: ImagePipeline

  init(
    store: DocumentStore,
    filterState: FilterState,
    errorController: ErrorController
  ) {
    self.store = store
    self.filterState = filterState
    self.errorController = errorController
    prefixLimit = initialLimit
    let prefetchPipeline = store.imagePipeline
    self.prefetchPipeline = prefetchPipeline
    imagePrefetcher = ImagePrefetcher(pipeline: prefetchPipeline)
    imagePrefetcher.didComplete = {
      Logger.shared.debug("Thumbnail prefetching completed")
    }
  }

  deinit {
    documentTask?.cancel()
    statusTask?.cancel()
    fill?.cancel()
  }

  // MARK: - Loading

  func load() async {
    Logger.shared.debug("DocumentListViewModel.load")
    // Idempotent: the observation owns `documents`, so a second `.task` firing
    // must not re-subscribe / re-fill.
    guard documentTask == nil else { return }

    // Up-to-date permissions (soft: a sync failure leaves cached perms in place).
    try? await store.fetchUISettings()
    guard hasViewPermission() else {
      noPermissions = true
      ready = true
      return
    }
    noPermissions = false

    guard let key = store.documentQueryKey(filter: filterState) else {
      // No caching backend (e.g. logged out) — nothing to show.
      ready = true
      return
    }
    subscribe(to: key, resettingWindow: true)
    do {
      try await runFill()
    } catch {
      // Initial load is silent: offline shows whatever is cached (or nothing),
      // never a toast. A user-initiated refresh is where errors surface.
      Logger.shared.error("Document fill failed (offline?): \(error)")
    }
    ready = true
  }

  func reload() async {
    Logger.shared.debug("DocumentListViewModel.reload")
    teardown()
    documents = []
    prefetchedIds = []
    ready = false
    await load()
  }

  /// Pull-to-refresh / filter change: re-sync elements, re-point the observation
  /// if the query changed, and re-fill from the network.
  ///
  /// The element sync and the document fill are independent network passes that
  /// both fail when offline. We collect the *first* error and surface a single
  /// toast at the end, so a pull-to-refresh while offline doesn't stack two
  /// identical alerts.
  func refresh(filter: FilterState? = nil, userInitiated: Bool = false) async {
    if let filter { filterState = filter }

    var firstError: (any Error)?
    do {
      try await store.fetchAll(userInitiated: userInitiated)
    } catch {
      Logger.shared.error("Element sync during refresh failed: \(error)")
      firstError = error
    }

    guard hasViewPermission() else {
      noPermissions = true
      surface(firstError, userInitiated: userInitiated)
      return
    }
    noPermissions = false

    guard let key = store.documentQueryKey(filter: filterState) else {
      surface(firstError, userInitiated: userInitiated)
      return
    }
    if key != queryKey {
      subscribe(to: key, resettingWindow: true)
    }
    do {
      try await runFill()
    } catch {
      Logger.shared.error("Document fill failed (offline?): \(error)")
      if firstError == nil { firstError = error }
    }

    surface(firstError, userInitiated: userInitiated)
  }

  private func surface(_ error: (any Error)?, userInitiated: Bool) {
    guard userInitiated, let error else { return }
    errorController.push(error: error)
  }

  /// Kick the eager fill: page 1 awaited (DB write → observation repaints), the
  /// rest paged in the background. Throws the underlying error so the caller
  /// decides whether to surface it (coalesced with the element-sync error).
  private func runFill() async throws {
    isFetching = true
    defer { isFetching = false }
    fill?.cancel()
    let handle = try await store.fillDocumentQuery(filter: filterState)
    fill = handle
    // Adopt the fill's authoritative count immediately. `observeQueryStatus`
    // would deliver the same number, but only a beat *after* the page-1 write
    // — and in that beat `documents` is still the pre-emission `[]`. Without
    // this, switching to a not-yet-cached view momentarily reads as
    // `documents.isEmpty && !isFetching && totalCount == 0` and flashes
    // "No documents" before the observation repaints. Setting it here keeps
    // the empty-state guard on the loading branch until the rows arrive.
    totalCount = handle.totalCount
  }

  // MARK: - Growing-prefix windowing (no network)

  func fetchMoreIfNeeded(currentIndex: Int) {
    guard let key = queryKey else { return }
    // Only grow, and only when the prefix is actually full (more may exist).
    guard documents.count >= prefixLimit else { return }
    guard currentIndex + fetchMargin >= prefixLimit else { return }
    prefixLimit += widenStep
    startDocumentObservation(key, limit: prefixLimit)
  }

  // MARK: - Observation

  private func subscribe(to key: QueryKey, resettingWindow: Bool) {
    queryKey = key
    if resettingWindow {
      prefixLimit = initialLimit
      prefetchedIds = []
    }
    startStatusObservation(key)
    startDocumentObservation(key, limit: prefixLimit)
  }

  private func startDocumentObservation(_ key: QueryKey, limit: Int) {
    documentTask?.cancel()
    documentTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        for try await docs in store.observeDocumentPrefix(queryKey: key, limit: limit) {
          documents = docs
          prefetchThumbnails(for: docs)
        }
      } catch is CancellationError {
      } catch {
        Logger.shared.error("Document observation terminated: \(error)")
      }
    }
  }

  private func startStatusObservation(_ key: QueryKey) {
    statusTask?.cancel()
    statusTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        for try await status in store.observeQueryStatus(queryKey: key) {
          totalCount = status.totalCount
        }
      } catch is CancellationError {
      } catch {
        Logger.shared.error("Query-status observation terminated: \(error)")
      }
    }
  }

  private func teardown() {
    documentTask?.cancel()
    documentTask = nil
    statusTask?.cancel()
    statusTask = nil
    fill?.cancel()
    fill = nil
    queryKey = nil
  }

  // MARK: - Permissions / inbox helpers

  private func hasViewPermission() -> Bool {
    store.permissions.test(.view, for: .document)
  }

  func hasInboxTags(document: Document) -> Bool {
    document.tags.contains { store.tags[$0]?.isInboxTag == true }
  }

  func removeInboxTags(document: Document) async {
    guard hasInboxTags(document: document) else { return }
    var document = document
    let inboxTagIDs = Set(store.tags.values.filter(\.isInboxTag).map(\.id))
    document.tags.removeAll { inboxTagIDs.contains($0) }
    _ = try? await store.updateDocument(document)
  }

  // MARK: - Thumbnail prefetch

  private func prefetchThumbnails(for documents: [Document]) {
    let fresh = documents.filter { prefetchedIds.insert($0.id).inserted }
    guard !fresh.isEmpty else { return }
    let requests =
      fresh
      .compactMap { try? store.repository.thumbnailRequest(document: $0) }
      .map { ImageRequest(urlRequest: $0, processors: [.resize(width: 130)]) }
    guard !requests.isEmpty else { return }
    updatePrefetcherIfNeeded()
    imagePrefetcher.startPrefetching(with: requests)
  }

  private func updatePrefetcherIfNeeded() {
    let pipeline = store.imagePipeline
    guard pipeline !== prefetchPipeline else { return }
    imagePrefetcher.stopPrefetching()
    prefetchPipeline = pipeline
    imagePrefetcher = ImagePrefetcher(pipeline: pipeline)
    imagePrefetcher.didComplete = {
      Logger.shared.debug("Thumbnail prefetching completed")
    }
  }
}
