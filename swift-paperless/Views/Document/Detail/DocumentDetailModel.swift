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
    case loaded(PDFThumbnail)
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
    enum EditMode {
        case none
        case closing
        case correspondent
        case documentType
        case storagePath
        case created

        var color: Color {
            switch self {
            case .correspondent: .paletteYellow
            case .documentType: .paletteRed
            case .storagePath: .paletteCoolGray
            default: .gray
            }
        }
    }

    enum Detent: RawRepresentable, CaseIterable {
        case small
        case medium
        case large

        init?(rawValue _: PresentationDetent) {
            nil
        }

        var rawValue: PresentationDetent {
            switch self {
            case .small: .fraction(0.3)
            case .medium: .medium
            case .large: .large
            }
        }
    }

    @ObservationIgnored
    static let previewDetents: [PresentationDetent] = Detent.allCases.map(\.rawValue)

    private var detentStack: [PresentationDetent] = []

    var detent = Detent.medium.rawValue
//    var previewDetentOnFocus: PresentationDetent? = nil

    var editMode = EditMode.none
    var zIndexActive = EditMode.none
    var editingViewId = UUID()

    var isEditing: Bool {
        editMode != .none
    }

    var download: DocumentDownloadState = .initial
    var downloadProgress: Double = 0.0

    var showPreviewSheet = false

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

    func push(detent: Detent) {
        detentStack.append(self.detent)
        self.detent = detent.rawValue
    }

    func popDetent() {
        guard !detentStack.isEmpty else { return }
        detent = detentStack.removeLast()
    }

    func startEditing(_ mode: EditMode) {
        guard editMode == .none else { return }
        editingViewId = UUID()
        Haptics.shared.impact(style: .light)
        zIndexActive = mode
        Task {
            try? await Task.sleep(for: .seconds(0.05))
            editMode = mode
        }
    }

    func stopEditing() async {
        editMode = .closing
        try? await Task.sleep(for: .seconds(0.5))
        editMode = .none
        zIndexActive = .none
    }

    func loadMetadata() async {
        do {
            metadata = try await store.repository.metadata(documentId: document.id)
        } catch is CancellationError {
        } catch {
            Logger.shared.error("Error loading document metadata: \(error)")
            //                                        errorController.push(error: error)
        }
    }

    func onProgress(_: Double) {}

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

                guard let view = PDFThumbnail(file: url) else {
                    download = .error
                    return
                }
                download = .loaded(view)
                setLoading.cancel()
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
