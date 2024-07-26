//
//  DocumentDetailModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.06.2024.
//

import Foundation
import os
import SwiftUI

enum DocumentDownloadState: Equatable {
    case initial
    case loading
    case loaded(URL)
    case error

    static func == (lhs: DocumentDownloadState, rhs: DocumentDownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.initial, .initial), (.loading, .loading), (.loaded, .loaded), (.error, .error):
            true
        default:
            false
        }
    }
}

@MainActor
@Observable
class DocumentDetailModel {
    var download: DocumentDownloadState = .initial
    var downloadProgress: Double = 0.0

    @ObservationIgnored
    var store: DocumentStore

    var document: Document

    var suggestions: Suggestions?

    var metadata: Metadata?

    init(
        store: DocumentStore, document: Document
    ) {
        self.store = store
        self.document = document
    }

    func loadMetadata() async {
        do {
            metadata = try await store.repository.metadata(documentId: document.id)
        } catch is CancellationError {
        } catch {
            Logger.shared.error("Error loading document metadata: \(error)")
        }
    }

    func loadDocument() async {
        switch download {
        case .initial:
            let setLoading = Task {
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                download = .loading
            }
            do {
                guard let url = try await store.repository.download(documentID: document.id, progress: { @Sendable value in
                    Task { @MainActor in
                        self.downloadProgress = value
                    }
                }) else {
                    download = .error
                    return
                }

                download = .loaded(url)
                setLoading.cancel()
            } catch is CancellationError {
            } catch {
                download = .error
                Logger.shared.error("Unable to get document downloaded for preview rendering: \(error)")
                return
            }

        default:
            break
        }
    }

    func saveDocument() async throws {
        try await store.updateDocument(document)
    }

    func loadSuggestions() async throws {
        suggestions = try await store.repository.suggestions(documentId: document.id)
    }
}
