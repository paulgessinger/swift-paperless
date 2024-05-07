//
//  DocumentDetailView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import os
import SwiftUI

private enum DownloadState {
    case initial
    case loading
    case loaded(PDFThumbnail)
    case error
}

struct DocumentPreview: View {
    @State private var download = DownloadState.initial
    var document: Document

    var body: some View {
        IntegratedDocumentPreview(download: $download, document: document)
    }
}

private struct IntegratedDocumentPreview: View {
    @EnvironmentObject private var store: DocumentStore
    @Binding var download: DownloadState
    var document: Document

    private func loadDocument() async {
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
                withAnimation {
                    download = .loaded(view)
                }

            } catch {
                download = .error
                Logger.shared.error("Unable to get document downloaded for preview rendering: \(error)")
                return
            }

        default:
            break
        }
    }

    var body: some View {
        ZStack {
            HStack {
                AuthAsyncImage {
                    try? await store.repository.thumbnail(document: document)
                } content: { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .blur(radius: 5)

                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.gray, lineWidth: 0.33))
                        .shadow(color: Color("ImageShadow"), radius: 15)
                }
                placeholder: {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .aspectRatio(1.0, contentMode: .fit)
                }
            }

            switch download {
            case .error:
                HStack {
                    Spacer()
                    Label("Unable to load preview", systemImage: "eye.slash")
                        .labelStyle(.iconOnly)
                        .imageScale(.large)

                    Spacer()
                }

            case let .loaded(view):
                view
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(.gray, lineWidth: 0.33))
                    .shadow(color: Color("ImageShadow"), radius: 15)

            default:
                EmptyView()
            }
        }
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

struct DocumentDetailView: View {
    @EnvironmentObject private var store: DocumentStore

    @State var document: Document
    var navPath: Binding<NavigationPath>?

    @State private var editing = false
    @State private var download: DownloadState = .initial
    @State private var previewUrl: URL?

    @State private var tags: [Tag] = []

    @State private var relatedDocuments: [Document]? = nil

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var errorController: ErrorController

    var gray: Color {
        if colorScheme == .dark {
            return Color.secondarySystemGroupedBackground
        } else {
            return Color.systemGroupedBackground
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
                                Aspect(String(localized: .localizable.documentAsn(asn)), systemImage: "qrcode")
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
                                Aspect(String(localized: .localizable.correspondentNotAssignedPicker), systemImage: "person")
                                    .foregroundColor(Color.gray)
                                    .opacity(0.5)
                            }

                            if let id = document.documentType, let name = store.documentTypes[id]?.name {
                                Aspect(name, systemImage: "doc")
                                    .foregroundColor(Color.orange)
                            } else {
                                Aspect(String(localized: .localizable.documentTypeNotAssignedPicker), systemImage: "doc")
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
                                Aspect(String(localized: .localizable.storagePathNotAssignedPicker), systemImage: "archivebox")
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

        .onChange(of: store.documents) { _ in
            if let document = store.documents[document.id] {
                self.document = document
            }
        }

        .toolbar {
            Button(String(localized: .localizable.edit)) {
                editing.toggle()
            }
        }

        .sheet(isPresented: $editing) {
            DocumentEditView(document: $document, navPath: navPath)
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
                    DocumentDetailView(document: document, navPath: $navPath)
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
