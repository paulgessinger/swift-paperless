//
//  DocumentDetailViewV1.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
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

private struct Aspect<Content: View>: View {
    var label: Content
    var systemImage: String

    @ScaledMetric(relativeTo: .body) var imageWidth = 20.0

    init(systemImage: String, content: @escaping () -> Content) {
        self.systemImage = systemImage
        label = content()
    }

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .frame(width: imageWidth, alignment: .leading)
            label
        }
    }
}

private extension Aspect where Content == Text {
    init(_ label: String, systemImage: String) {
        self.label = Text(label)
        self.systemImage = systemImage
    }
}

struct DocumentDetailViewV1: DocumentDetailViewProtocol {
    @ObservedObject private var store: DocumentStore
    @State var document: Document
    var navPath: Binding<NavigationPath>?

    @State private var editing = false
    @State private var download: DownloadState = .initial
    @State private var previewUrl: URL?

    @State private var tags: [Tag] = []

    @State private var relatedDocuments: [Document]? = nil

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var errorController: ErrorController

    init(store: DocumentStore,
         document: Document,
         navPath: Binding<NavigationPath>? = nil)
    {
        self.store = store
        self.document = document
        self.navPath = navPath
    }

    var gray: AnyShapeStyle {
        if colorScheme == .dark {
            .init(.background.tertiary)
        } else {
            .init(.background.secondary)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading) {
                    Text(document.title)
                        .font(.title)
                        .bold()
                        .padding(.bottom)
                    HStack(alignment: .top, spacing: 25) {
                        VStack(alignment: .leading) {
                            if let asn = document.asn {
                                Aspect(String(localized: .localizable(.documentAsn(asn))), systemImage: "qrcode")
                            } else {
                                Aspect(systemImage: "qrcode") {
                                    HStack(spacing: 2) {
                                        Text(String("#"))
                                        Text(String("0000"))
                                            .redacted(reason: .placeholder)
                                    }
                                }
                            }

                            if let id = document.correspondent, let name = store.correspondents[id]?.name {
                                Aspect(name, systemImage: "person")
                                    .foregroundColor(Color.accentColor)
                            } else {
                                Aspect(String(localized: .localizable(.correspondentNotAssignedPicker)), systemImage: "person")
                                    .foregroundColor(Color.gray)
                                    .opacity(0.5)
                            }

                            if let id = document.documentType, let name = store.documentTypes[id]?.name {
                                Aspect(name, systemImage: "doc")
                                    .foregroundColor(Color.orange)
                            } else {
                                Aspect(String(localized: .localizable(.documentTypeNotAssignedPicker)), systemImage: "doc")
                                    .foregroundColor(Color.gray)
                                    .opacity(0.5)
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading) {
                            Aspect(DocumentCell.dateFormatter.string(from: document.created), systemImage: "calendar")

                            if let id = document.storagePath, let name = store.storagePaths[id]?.name {
                                Aspect(name, systemImage: "archivebox")
                            } else {
                                Aspect(String(localized: .localizable(.storagePathNotAssignedPicker)), systemImage: "archivebox")
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }

                    TagsView(tags: document.tags.compactMap { store.tags[$0] })
                }
                .padding()

                IntegratedDocumentPreview(download: $download, document: document)
                    .padding()
                    .onTapGesture {
                        if case let .loaded(view) = download {
                            previewUrl = view.file
                        }
                    }
            }
        }

        .refreshable {
            do {
                if let document = try await store.document(id: document.id) {
                    self.document = document
                }
            } catch {
                Logger.shared.error("Error refreshing document \(document.id): \(error)")
                errorController.push(error: error)
            }
        }

        .quickLookPreview($previewUrl)
//                if let related = relatedDocuments {
//                    Group {
//                        Divider()
//                        HStack {
//                            Spacer()
//                            Text("Related documents")
//                                .foregroundColor(.gray)
//                            Spacer()
//                        }
//                        ForEach(related) { _ in Text("Doc") }
//                    }
//                    .transition(
//                        .opacity.combined(with: .move(edge: .bottom)))
//                }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: store.documents) {
            if let document = store.documents[document.id] {
                self.document = document
            }
        }

        .toolbar {
            Button(String(localized: .localizable(.edit))) {
                editing.toggle()
            }
            .accessibilityIdentifier("documentEditButton")
        }

        .sheet(isPresented: $editing) {
            DocumentEditView(store: store,
                             document: $document,
                             navPath: navPath)
        }
    }
}

private struct PreviewHelper: View {
    @EnvironmentObject var store: DocumentStore
    @State var document: Document?
    @State var navPath = NavigationPath()

    var body: some View {
        NavigationStack {
            VStack {
                if let document {
                    DocumentDetailViewV1(store: store, document: document, navPath: $navPath)
                }
            }
            .task {
                document = try? await store.document(id: 1)
            }
        }
    }
}

#Preview("DocumentDetailsView") {
    let store = DocumentStore(repository: PreviewRepository())

    return PreviewHelper()
        .environmentObject(store)
}
