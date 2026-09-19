//
//  DocumentListViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 14.05.2024.
//

import AppShared
import Common
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

  /// Assigned by the document observation; never a network fetch. Entries are
  /// `.loaded` documents or `.skeleton(id:)` placeholders for members whose
  /// object isn't cached yet.
  var documents: [DocumentEntry] = []
  var ready = false
  var noPermissions = false

  /// Server-reported total, from the query-status observation. Drives the count
  /// pill and the "has anything at all" gate — *not* the scroll extent, which
  /// follows the loaded prefix, since the list only ever renders `documents`.
  var totalCount: UInt?

  /// True while a fill (page-1 await) or refresh is in flight.
  private(set) var isFetching = false

  /// The observed query was just switched to and its fill hasn't reported back
  /// yet. Without this, the element sync that precedes a filter change's fill
  /// is a window in which an uncached query reads as "No documents".
  private var awaitingFill = false

  /// Why the most recent fill of the observed query stopped — at page 1 or
  /// while paging the rest — or `nil` if it hasn't failed. Scoped to the query
  /// on screen: switching queries clears it, and a superseded fill can't set it.
  private var fillError: (any Error)?

  /// The cached order is the observed query's complete membership (from the
  /// query-status observation). Tells a truncated cache from a whole one when
  /// the fill fails.
  private var isCacheComplete = false

  /// Another fill took the observed query over from the list's (see
  /// ``DocumentListFillTracking``), and the list is waiting for it to finish.
  private var isFollowingReplacement = false

  /// A fill that took the query over has ended, and the cache it left isn't
  /// complete. There is no error to show for it: it was another fill's.
  private var replacementStoppedShort = false

  /// What the list shows: rows, placeholders, the empty state, or the
  /// load-failure state — and whether the rows are a known-truncated answer.
  var state: DocumentListState {
    DocumentListState(
      hasRows: !documents.isEmpty,
      isFetching: isFetching || awaitingFill || isFollowingReplacement,
      totalCount: totalCount,
      isCacheComplete: isCacheComplete,
      fillFailed: fillError != nil || replacementStoppedShort)
  }

  /// Which list the failure belongs to, for wording it.
  var scope: DocumentListScope {
    DocumentListScope(
      savedView: filterState.savedView, modified: filterState.modified,
      filtering: filterState.filtering)
  }

  /// The failed fill's error, as the user-facing text the error banners use.
  var fillErrorDescription: String? {
    fillError.map { errorController.describe($0) }
  }

  /// The failed fill's error with its headline and full text kept apart, for
  /// surfaces too small for the whole description.
  var fillFailure: (any DisplayableError)? {
    fillError.map { errorController.displayableError(for: $0) }
  }

  // Growing-prefix state.
  @ObservationIgnored private var queryKey: QueryKey?
  @ObservationIgnored private var prefixLimit: Int
  @ObservationIgnored private nonisolated(unsafe) var fill: QueryFillHandle?
  @ObservationIgnored private nonisolated(unsafe) var documentTask: Task<Void, Never>?
  @ObservationIgnored private nonisolated(unsafe) var statusTask: Task<Void, Never>?
  @ObservationIgnored private nonisolated(unsafe) var completionTask: Task<Void, Never>?
  /// Bumped whenever the list moves on from a fill (a newer fill, a query
  /// switch, a teardown), so an older fill's late outcome is dropped rather
  /// than reported against whatever is on screen now.
  @ObservationIgnored private var fillGeneration = 0

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
    completionTask?.cancel()
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
      // Initial load never toasts: offline shows whatever is cached. A failure
      // still reaches the list itself through `state`, so an empty cache reads
      // as "couldn't load", not as "no documents".
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
    if let filter {
      filterState = filter
      // Switch the observation before the element sync, not after it: the sync
      // can take a full timeout when the server is unreachable, and for that
      // whole time the list would otherwise keep showing the previous query's
      // rows — or its failure — under the new filter.
      if let key = store.documentQueryKey(filter: filter), key != queryKey {
        subscribe(to: key, resettingWindow: true)
      }
    }

    // Say "offline" up front: the passes below mostly fall back to the cache
    // rather than throwing, so waiting for an error would say nothing at all.
    // Remembered, so the error path below doesn't say it a second time.
    let announcedOffline = userInitiated && errorController.noteOfflineIfNeeded()

    var firstError: (any Error)?
    do {
      try await store.sync(userInitiated: userInitiated)
    } catch {
      Logger.shared.error("Element sync during refresh failed: \(error)")
      firstError = error
    }

    guard hasViewPermission() else {
      noPermissions = true
      awaitingFill = false
      surface(firstError, userInitiated: userInitiated, announcedOffline: announcedOffline)
      return
    }
    noPermissions = false

    guard let key = store.documentQueryKey(filter: filterState) else {
      awaitingFill = false
      surface(firstError, userInitiated: userInitiated, announcedOffline: announcedOffline)
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

    // The list already says the load failed, in place; a toast on top would
    // report the same thing twice.
    let state = state
    if fillError != nil, state.content == .unavailable || state.isIncomplete {
      return
    }
    surface(firstError, userInitiated: userInitiated, announcedOffline: announcedOffline)
  }

  /// The load-failure state's retry: fill the query on screen again.
  ///
  /// Only the fill, not a whole `refresh`: the element sync that runs first
  /// there can sit out a full timeout against an unreachable server, during
  /// which the tap would appear to do nothing. The fill flips the list to
  /// placeholders at once. Not a user-initiated refresh as far as errors go —
  /// the outcome shows in the list itself — but an offline device still gets
  /// the offline indicator, so the tap visibly answers.
  func retry() async {
    guard queryKey != nil else { return }
    errorController.noteOfflineIfNeeded()
    do {
      try await runFill()
    } catch {
      Logger.shared.error("Document fill retry failed: \(error)")
    }
  }

  private func surface(_ error: (any Error)?, userInitiated: Bool, announcedOffline: Bool) {
    guard userInitiated, !announcedOffline, let error else { return }
    errorController.push(readError: error)
  }

  /// Kick the eager fill: page 1 awaited (DB write → observation repaints), the
  /// rest paged in the background. Throws the underlying error so the caller
  /// decides whether to surface it (coalesced with the element-sync error).
  ///
  /// A failure is also recorded as `fillError` for the query on screen — page 1
  /// here, the background paging via `watchCompletion` — so the list can tell a
  /// failed load from a query with no matches.
  private func runFill() async throws {
    isFetching = true
    defer { isFetching = false }
    fill?.cancel()
    fillGeneration += 1
    let generation = fillGeneration
    // This fill takes the key back from whatever the list was following.
    isFollowingReplacement = false
    replacementStoppedShort = false
    do {
      let handle = try await store.fillDocumentQuery(filter: filterState)
      // A newer fill (or a query switch) started while page 1 was in flight:
      // this outcome no longer describes the list on screen.
      guard generation == fillGeneration else { return }
      fill = handle
      // Adopt the fill's authoritative count immediately. `observeQueryStatus`
      // would deliver the same number, but only a beat *after* the page-1 write
      // — and in that beat `documents` is still the pre-emission `[]`. Without
      // this, switching to a not-yet-cached view momentarily reads as
      // `documents.isEmpty && !isFetching && totalCount == 0` and flashes
      // "No documents" before the observation repaints. Setting it here keeps
      // the empty-state guard on the loading branch until the rows arrive.
      totalCount = handle.totalCount
      fillError = nil
      awaitingFill = false
      watchCompletion(of: handle, generation: generation)
    } catch {
      if generation == fillGeneration {
        awaitingFill = false
        if !error.isCancellationError {
          fillError = error
        }
      }
      throw error
    }
  }

  /// Follow the background paging to its end. Its failure is otherwise only
  /// logged by the repository, leaving the list stopped at whatever page it
  /// reached with nothing to say it is incomplete.
  private func watchCompletion(of handle: QueryFillHandle, generation: Int) {
    completionTask?.cancel()
    completionTask = Task { @MainActor [weak self] in
      let end: DocumentListFillTracking.End
      var failure: (any Error)?
      do {
        try await handle.awaitCompletion()
        end = .finished
      } catch let error where error.isCancellationError {
        end = .cancelled
      } catch {
        end = .failed
        failure = error
      }
      guard let self else { return }
      // Every cancellation the list causes itself bumps the generation first,
      // so a cancellation that is still current came from another fill.
      switch DocumentListFillTracking.followUp(
        after: end, isCurrent: generation == fillGeneration)
      {
      case .none:
        return
      case .recordFailure:
        if let failure {
          Logger.shared.error("Document fill stopped before the end of the query: \(failure)")
        }
        fillError = failure
      case .followReplacement:
        await followReplacement(of: handle.queryKey, generation: generation)
      }
    }
  }

  /// Another fill (the library sweep, typically) took the query over and
  /// cancelled the list's. Wait for the key's writers to finish, then judge the
  /// outcome from the cache, since the replacement's error isn't visible here.
  /// Meanwhile the list counts as fetching: something is filling its query.
  private func followReplacement(of key: QueryKey, generation: Int) async {
    Logger.shared.info("Document fill was taken over by another fill; following it")
    isFollowingReplacement = true
    await store.waitForQueryWriters(queryKey: key)
    let status = try? await store.queryStatus(queryKey: key)
    // The list moved on while waiting: a newer fill or query switch owns the
    // state now, and has reset it.
    guard generation == fillGeneration else { return }
    isFollowingReplacement = false
    // Read the status here rather than trust the observation, which lands a
    // beat after the replacement's final write.
    if let status { isCacheComplete = status.isComplete }
    if DocumentListFillTracking.replacementStoppedShort(isCacheComplete: isCacheComplete) {
      Logger.shared.error("The fill that took over the document list stopped short")
      replacementStoppedShort = true
    }
  }

  // MARK: - Viewed stamp

  /// The list is on screen again, e.g. returned to from a pushed document. Its
  /// first appearance has no key yet; `subscribe` stamps that one.
  ///
  /// Not re-sent on foregrounding, which fires no appear. It doesn't need to be:
  /// the *Recently browsed* cap only runs before any list is open.
  func noteAppeared() {
    guard let queryKey else { return }
    markViewed(queryKey)
  }

  private func markViewed(_ key: QueryKey) {
    Task { [store] in await store.markDocumentQueryViewed(key) }
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
    // A list newly on screen: the first load, a filter change, a view switch.
    markViewed(key)
    if resettingWindow {
      prefixLimit = initialLimit
      prefetchedIds = []
    }
    // A different query: the previous one's fill outcome says nothing about
    // this one, and its fill is not ours to report any more.
    fillGeneration += 1
    completionTask?.cancel()
    completionTask = nil
    fillError = nil
    isFollowingReplacement = false
    replacementStoppedShort = false
    isCacheComplete = false
    awaitingFill = true
    startStatusObservation(key)
    startDocumentObservation(key, limit: prefixLimit)
  }

  private func startDocumentObservation(_ key: QueryKey, limit: Int) {
    documentTask?.cancel()
    documentTask = Task { @MainActor [weak self] in
      // Re-check `self` inside the loop, not before it: a `guard let self` out
      // here stays strong across every suspension, and this task is stored on
      // the view model — so neither would ever deallocate.
      guard let store = self?.store else { return }
      do {
        for try await docs in store.observeDocumentPrefix(queryKey: key, limit: limit) {
          guard let self else { break }
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
      guard let store = self?.store else { return }
      do {
        for try await status in store.observeQueryStatus(queryKey: key) {
          guard let self else { break }
          totalCount = status.totalCount
          isCacheComplete = status.isComplete
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
    completionTask?.cancel()
    completionTask = nil
    fill?.cancel()
    fill = nil
    queryKey = nil
    fillGeneration += 1
    fillError = nil
    isFollowingReplacement = false
    replacementStoppedShort = false
    isCacheComplete = false
    awaitingFill = false
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
    // A successful update also takes the document out of the lists it no
    // longer matches — this one included, when it is an inbox view (see
    // `CachingRepository.update(document:)`). A failed one changes nothing
    // locally, so the row simply stays; say why, or the swipe looks ignored.
    do {
      _ = try await store.updateDocument(document)
    } catch let error where !error.isCancellationError {
      Logger.shared.error("Removing inbox tags failed: \(error)")
      errorController.push(mutationError: error)
    } catch {}
  }

  // MARK: - Thumbnail prefetch

  private func prefetchThumbnails(for entries: [DocumentEntry]) {
    // Skeletons have no thumbnail to fetch.
    let fresh = entries.compactMap(\.document).filter { prefetchedIds.insert($0.id).inserted }
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
