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
import SwiftUI
import os

@MainActor
@Observable
class DocumentListViewModel {
  private var store: DocumentStore
  private var filterState: FilterState
  private var errorController: ErrorController

  var documents: [Document] = []
  var ready = false

  var noPermissions = false

  // Total document count reported by the server. nil until the first page is
  // fetched, or when the active source has no notion of a server-side total.
  var totalCount: UInt?

  private var inFlight: Int = 0
  var isFetching: Bool { inFlight > 0 }

  private var source: (any DocumentSource)?
  private var exhausted: Bool = false
  // Guards against concurrent fetchMoreIfNeeded calls. Cells near the bottom
  // can each fire `.task` near-simultaneously when a batch first appears,
  // and without this guard each one would launch a paged fetch.
  private var loadingMore: Bool = false
  // Tracks document IDs we've already added so we can dedup paged responses.
  // The server can return the same document on adjacent pages if a new doc
  // is inserted between fetches and shifts the page offsets — without dedup
  // this surfaces as a SwiftUI ForEach duplicate-ID warning and stutters.
  private var seenIds: Set<UInt> = []

  private var initialBatchSize: UInt = 250
  private var batchSize: UInt = 250
  private var fetchMargin = 10
  private let highPriorityPrefetchCount = 10

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
    let prefetchPipeline = store.imagePipeline
    self.prefetchPipeline = prefetchPipeline
    imagePrefetcher = ImagePrefetcher(pipeline: prefetchPipeline)

    imagePrefetcher.didComplete = {
      Logger.shared.debug("Thumbnail prefetching completed")
    }
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

  func reload() async {
    Logger.shared.debug("DocumentListViewModel.reload")
    documents = []
    seenIds = []
    source = nil
    await load()
    try? await Task.sleep(for: .seconds(0.1))
    ready = true
  }

  private func ensurePermissions() throws {
    guard store.permissions.test(.view, for: .document) else {
      throw PermissionsError(resource: .document, operation: .view)
    }
    noPermissions = false
  }

  func load() async {
    Logger.shared.debug("DocumentListViewModel.load")
    guard documents.isEmpty else { return }
    inFlight += 1
    defer { inFlight -= 1 }
    do {
      // Ensure we have up-to-date permissions
      try await store.fetchUISettings()
      if source == nil {
        source = try store.repository.documents(filter: filterState)
      }
      try ensurePermissions()
      let batch = try await source!.fetch(limit: initialBatchSize)
      totalCount = await source!.totalCount

      let requests: [ImageRequest] =
        try batch
        .enumerated()
        .map { index, document in
          let urlRequest = try store.repository.thumbnailRequest(document: document)
          let fullPriority: ImageRequest.Priority =
            index < highPriorityPrefetchCount ? .high : .normal
          return [
            ImageRequest(urlRequest: urlRequest, priority: fullPriority),
            ImageRequest(urlRequest: urlRequest, processors: [.resize(width: 130)]),
          ]
        }
        .flatMap { $0 }

      //      let requests =
      //    try batch
      //    .map { try store.repository.thumbnailRequest(document: $0) }
      //    .map { ImageRequest(urlRequest: $0, processors: [.resize(width: 130)]) }

      Logger.shared.debug("Prefetching \(requests.count) thumbnail images")
      updatePrefetcherIfNeeded()
      imagePrefetcher.startPrefetching(with: requests)

      documents = batch
      seenIds = Set(batch.map(\.id))
      Logger.shared.debug("DocumentListViewModel.load loading complete")
    } catch let error as PermissionsError {
      noPermissions = true
      Logger.shared.warning("Insufficient permissions to load documents: \(error)")
    } catch {
      Logger.shared.error("DocumentList failed to load documents: \(error)")
      errorController.push(error: error)
    }
  }

  func fetchMoreIfNeeded(currentIndex: Int) async {
    if exhausted || loadingMore { return }
    guard currentIndex >= documents.count - fetchMargin else { return }
    loadingMore = true
    let repository = store.repository
    let highPriorityCount = highPriorityPrefetchCount
    Task.detached {
      defer { Task { @MainActor in self.loadingMore = false } }
      do {
        Logger.shared.info("Fetching additional documents")
        guard let source = await self.source else {
          return
        }

        let batch = try await source.fetch(limit: self.batchSize)
        let sourceExhausted = await source.isExhausted
        let sourceTotal = await source.totalCount
        if batch.isEmpty {
          await MainActor.run {
            self.exhausted = true
          }
          return
        }

        let requests =
          try batch
          .enumerated()
          .map { index, document in
            let urlRequest = try repository.thumbnailRequest(document: document)
            let fullPriority: ImageRequest.Priority =
              index < highPriorityCount ? .high : .normal
            return [
              ImageRequest(urlRequest: urlRequest, priority: fullPriority),
              ImageRequest(urlRequest: urlRequest, processors: [.resize(width: 130)]),
            ]
          }
          .flatMap { $0 }

        Logger.shared.debug("Prefetching \(requests.count) thumbnail images")
        await self.updatePrefetcherIfNeeded()
        await self.imagePrefetcher.startPrefetching(with: requests)

        await MainActor.run {
          let fresh = batch.filter { self.seenIds.insert($0.id).inserted }
          self.documents += fresh
          if let sourceTotal {
            self.totalCount = sourceTotal
          }
          if sourceExhausted {
            self.exhausted = true
          }
        }
      } catch {
        Logger.shared.error("DocumentList failed to load more if needed: \(error)")
        await self.errorController.push(error: error)
      }
    }
  }

  func refresh(filter: FilterState? = nil, retain: Bool = false) async throws -> [Document] {
    inFlight += 1
    defer { inFlight -= 1 }
    try await store.fetchAll()

    if let filter {
      filterState = filter
    }
    exhausted = false
    do {
      try ensurePermissions()
      source = try store.repository.documents(filter: filterState)

      let batch = try await source!.fetch(limit: retain ? UInt(documents.count) : initialBatchSize)
      totalCount = await source!.totalCount
      seenIds = Set(batch.map(\.id))

      let requests =
        try batch
        .enumerated()
        .map { index, document in
          let urlRequest = try self.store.repository.thumbnailRequest(document: document)
          let fullPriority: ImageRequest.Priority =
            index < highPriorityPrefetchCount ? .high : .normal
          return [
            ImageRequest(urlRequest: urlRequest, priority: fullPriority),
            ImageRequest(urlRequest: urlRequest, processors: [.resize(width: 130)]),
          ]
        }
        .flatMap { $0 }

      Logger.shared.debug("Prefetching \(requests.count) thumbnail images")
      updatePrefetcherIfNeeded()
      imagePrefetcher.startPrefetching(with: requests)

      return batch
    } catch let error as PermissionsError {
      Logger.shared.error("Insufficient permissions to refresh documents: \(error)")
      noPermissions = true
      throw error
    } catch {
      Logger.shared.error("DocumentList failed to refresh: \(error)")
      errorController.push(error: error)
      throw error
    }
  }

  func replace(documents: [Document]) {
    self.documents = documents
    seenIds = Set(documents.map(\.id))
  }

  func removed(document: Document) {
    documents.removeAll(where: { $0.id == document.id })
    seenIds.remove(document.id)
  }

  func updated(document: Document) {
    if let target = documents.firstIndex(where: { $0.id == document.id }) {
      documents[target] = document
    }
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
}
