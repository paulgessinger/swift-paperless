//
//  DocumentListViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 14.05.2024.
//

import Foundation
import Nuke
import os
import SwiftUI

@MainActor
class DocumentListViewModel: ObservableObject {
    private var store: DocumentStore
    private var filterState: FilterState
    private var errorController: ErrorController

    @Published var documents: [Document] = []
    @Published var loading = false
    @Published var ready = false

    private var source: (any DocumentSource)?
    private var exhausted: Bool = false

    private var initialBatchSize: UInt = 250
    private var batchSize: UInt = 250
    private var fetchMargin = 10

    private var imagePrefetcher: ImagePrefetcher

    init(store: DocumentStore, filterState: FilterState, errorController: ErrorController) {
        self.store = store
        self.filterState = filterState
        self.errorController = errorController

        let dataloader = DataLoader()

        if let delegate = store.repository.delegate {
            dataloader.delegate = delegate
        }

        imagePrefetcher = ImagePrefetcher(pipeline: ImagePipeline(configuration: .init(dataLoader: dataloader)))

        imagePrefetcher.didComplete = {
            Logger.shared.debug("Thumbnail prefetching completed")
        }
    }

    func reload() async {
        documents = []
        source = nil
        await load()
        try? await Task.sleep(for: .seconds(0.1))
        ready = true
    }

    func load() async {
        guard documents.isEmpty, !loading else { return }
        loading = true
        do {
            if source == nil {
                source = try await store.repository.documents(filter: filterState)
            }
            let batch = try await source!.fetch(limit: initialBatchSize)

            let requests = try batch
                .map { try store.repository.thumbnailRequest(document: $0) }
                .map { ImageRequest(urlRequest: $0, processors: [.resize(width: 130)]) }

            Logger.shared.debug("Prefetching \(requests.count) thumbnail images")
            imagePrefetcher.startPrefetching(with: requests)

            documents = batch
            loading = false
        } catch {
            Logger.shared.error("DocumentList failed to load documents: \(error)")
            errorController.push(error: error)
        }
    }

    func fetchMoreIfNeeded(currentIndex: Int) async {
        if exhausted { return }
        if currentIndex >= documents.count - fetchMargin {
            guard !loading else { return }
            await MainActor.run { loading = true }
            let repository = store.repository
            Task.detached {
                do {
                    Logger.shared.info("Fetching additional documents")
                    guard let source = await self.source else {
                        return
                    }
                    let batch = try await source.fetch(limit: self.batchSize)
                    if batch.isEmpty {
                        await MainActor.run {
                            self.exhausted = true
                            self.loading = false
                        }
                        return
                    }

                    let requests = try batch
                        .map { try repository.thumbnailRequest(document: $0) }
                        .map { ImageRequest(urlRequest: $0, processors: [.resize(width: 130)]) }

                    Logger.shared.debug("Prefetching \(requests.count) thumbnail images")
                    await self.imagePrefetcher.startPrefetching(with: requests)

                    await MainActor.run {
                        self.documents += batch
                        self.loading = false
                    }
                } catch {
                    Logger.shared.error("DocumentList failed to load more if needed: \(error)")
                    await self.errorController.push(error: error)
                }
            }
        }
    }

    func refresh(filter: FilterState? = nil, retain: Bool = false) async throws -> [Document] {
        if let filter {
            filterState = filter
        }
        exhausted = false
        do {
            source = try await store.repository.documents(filter: filterState)
            guard let source else {
                return []
            }

            let batch = try await source.fetch(limit: retain ? UInt(documents.count) : initialBatchSize)

            let requests = try batch
                .map { try self.store.repository.thumbnailRequest(document: $0) }
                .map { ImageRequest(urlRequest: $0, processors: [.resize(width: 130)]) }

            Logger.shared.debug("Prefetching \(requests.count) thumbnail images")
            imagePrefetcher.startPrefetching(with: requests)

            return batch
        } catch {
            Logger.shared.error("DocumentList failed to refresh: \(error)")
            errorController.push(error: error)
            throw error
        }
    }

    func replace(documents: [Document]) {
        self.documents = documents
    }

    func removed(document: Document) {
        documents.removeAll(where: { $0.id == document.id })
    }

    func updated(document: Document) {
        if let target = documents.firstIndex(where: { $0.id == document.id }) {
            documents[target] = document
        }
    }

    func removeInboxTags(document: Document) async {
        var document = document
        let inboxTags = store.tags.values.filter(\.isInboxTag)
        for tag in inboxTags {
            document.tags.removeAll(where: { $0 == tag.id })
        }
        _ = try? await store.updateDocument(document)
    }
}
