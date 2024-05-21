//
//  DocumentDetailView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

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
        .shadow(color: Color("ImageShadow"), radius: 15)

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

    @State private var editing = true
    @State private var download: DownloadState = .initial
    @State private var previewUrl: URL?

    @State private var tags: [Tag] = []

    @State private var relatedDocuments: [Document]? = nil

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var errorController: ErrorController

    @MainActor
    private static let editDetents: [PresentationDetent] = [
        //        .fraction(0.1),
        .height(bottomPadding),
        .medium,
        .large,
    ]
    @State private var editDetent = Self.editDetents.first!

    private static let bottomPadding: CGFloat = 100

    var gray: Color {
        if colorScheme == .dark {
            return Color.secondarySystemGroupedBackground
        } else {
            return Color.systemGroupedBackground
        }
    }

    var body: some View {
//        VStack {
//            Text(document.title)
//                .font(.title)
//                .bold()
//                .frame(maxWidth: .infinity, alignment: .leading)
//                .padding()
        DocumentQuickLookPreview(document: document)
//                .safeAreaInset(edge: .top) {
//                    VStack {
//                        Text("Hi")
//                        Text("HO")
//                        Text("Yo")
//                    }
//                }
//                .safeAreaInset(edge: .bottom) {
//                    VStack {
//                        Text("Hi")
//                        Text("HO")
//                        Text("Yo")
//                    }
//                }
            .safeAreaPadding(.bottom, Self.bottomPadding)
            .background(Color(white: 0.9)) // empirical color

//            .safeAreaInset(edge: .bottom) {
//                Rectangle()
//                    .fill(Color.systemBackground)
//            }
//            .ignoresSafeArea(.container, edges: [.top])
//                .navigationTitle("_")
//        }

//        .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)

            .onChange(of: store.documents) { _ in
                if let document = store.documents[document.id] {
                    self.document = document
                }
            }

            .toolbarBackground(.thinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)

            .sheet(isPresented: $editing) {
                DocumentEditView(document: $document, navPath: navPath)
                    .presentationDetents(Set(Self.editDetents), selection: $editDetent)
                    .presentationBackgroundInteraction(
                        .enabled(upThrough: .medium)
                    )
                    .interactiveDismissDisabled()
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
//        }
//        .overlay(alignment: .top) {
//            VStack {
//                Text("HALLO")
//            }
//            .padding(.top, 70)
//            .padding(.bottom, 5)
//            .frame(maxWidth: .infinity)
//            .background {
//                Rectangle()
//                    .fill(.thinMaterial)
//            }
//            .ignoresSafeArea(.container, edges: .top)
        }
    }
}

#Preview("DocumentDetailsView") {
    let store = DocumentStore(repository: PreviewRepository())
    @StateObject var errorController = ErrorController()

    return PreviewHelper()
        .environmentObject(store)
        .environmentObject(errorController)
}
