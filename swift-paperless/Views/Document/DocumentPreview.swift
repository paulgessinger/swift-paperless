//
//  DocumentPreview.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 11.09.25.
//

import DataModel
import NukeUI
import os
import SwiftUI

private enum DownloadState: Equatable {
    case initial
    case loading
    case loaded(PDFThumbnail)
    case error

    static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.initial, .initial), (.loading, .loading), (.loaded, .loaded), (.error, .error):
            true
        default:
            false
        }
    }
}

struct DocumentPreview: View {
    @State private var download = DownloadState.initial
    var document: Document

    var body: some View {
        IntegratedDocumentPreview(download: $download, document: document)
            .frame(minWidth: 200, minHeight: 200)
    }
}

private struct IntegratedDocumentPreview: View {
    @EnvironmentObject private var store: DocumentStore
    @Binding var download: DownloadState
    var document: Document

    @StateObject private var image = FetchImage()

    private func loadDocument() async {
        image.transaction = Transaction(animation: .linear(duration: 0.1))
        do {
            try image.load(ImageRequest(urlRequest: store.repository.thumbnailRequest(document: document)))
        } catch {
            Logger.shared.error("Error loading document thumbnail: \(error)")
        }

        switch download {
        case .initial:
            download = .loading
            do {
                guard let url = try await store.repository.download(documentID: document.id) else {
                    download = .error
                    return
                }

                guard let view = PDFThumbnail(file: url) else {
                    download = .error
                    return
                }
                download = .loaded(view)

            } catch {
                download = .error
                Logger.shared.error("Unable to get document downloaded for preview rendering: \(error)")
                return
            }

        default:
            break
        }
    }

    private var isLoaded: Bool {
        if case .loaded = download {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            image.image?
                .resizable()
                .scaledToFit()
                .blur(radius: 10)

            switch download {
            case .error:
                Label("Unable to load preview", systemImage: "eye.slash")
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
                    .frame(maxWidth: .infinity, alignment: .center)

            case let .loaded(view):
                view
                    .background(.white)

            default:
                EmptyView()
            }
        }

        .transition(.opacity)
        .animation(.easeOut(duration: 0.8), value: download)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(.gray, lineWidth: 0.33))
        .shadow(color: Color(.imageShadow), radius: 15)
        .task {
            await loadDocument()
        }
    }
}
