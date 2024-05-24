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

    @State private var showPreviewSheet = false
    @State private var download: DownloadState = .initial
    @State private var previewUrl: URL?

    @State private var tags: [Tag] = []

    @State private var relatedDocuments: [Document]? = nil

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var errorController: ErrorController

    @MainActor
    fileprivate static let editDetents: [PresentationDetent] = [
        //                .fraction(0.1),
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
                download = .loaded(view)
                showPreviewSheet = true

            } catch {
                download = .error
                Logger.shared.error("Unable to get document downloaded for preview rendering: \(error)")
                return
            }

        default:
            break
        }
    }

    private struct PreviewWrapper: View {
        @Binding var state: DownloadState
        @Binding var detent: PresentationDetent

        var body: some View {
            NavigationStack {
                if case let .loaded(thumb) = state {
                    QuickLookPreview(url: thumb.file)
                        //                    FullDocumentPreview(url: thumb.file)
                        .toolbarBackground(.visible, for: .navigationBar)
                        .toolbarBackground(Color(white: 0.4, opacity: 0.0), for: .navigationBar)
                        .navigationTitle(String(localized: .localizable.documentDetailPreviewTitle))
                        .ignoresSafeArea(.container, edges: [.bottom])
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                ShareLink(item: thumb.file) {
                                    Label(localized: .localizable.share, systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                }
            }
        }
    }

    @State var editing = false
    @Namespace private var animation

    private let delay = 0.1
    private let openDuration = 0.3
    private let closeDuration = 0.3
    //    private let animationType: Animation = .spring()
    @State private var text: String = ""

    var body: some View {
        VStack {
            if !editing {
                ScrollView(.vertical) {
                    VStack {
                        if !editing {
                            Text(document.title + document.title)
                                .font(.title)
                                .bold()
                                .frame(maxWidth: .infinity)

                            Grid {
                                GridRow {
                                    HStack {
                                        Label(localized: .localizable.documentType, systemImage: "doc.fill")
                                            .labelStyle(.iconOnly)
                                            .font(.title)

                                        if let id = document.correspondent, let name = store.correspondents[id]?.name {
                                            Text(name)
                                        } else {
                                            Text(.localizable.correspondentNotAssignedPicker)
                                        }
                                    }
                                    .foregroundStyle(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    .background {
                                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                                            .fill(Color("AccentColor"))
                                    }

                                    HStack {
                                        Label(localized: .localizable.documentType, systemImage: "doc.fill")
                                            .labelStyle(.iconOnly)
                                            .font(.title)

                                        if let id = document.correspondent, let name = store.correspondents[id]?.name {
                                            Text(name)
                                        } else {
                                            Text(.localizable.correspondentNotAssignedPicker)
                                        }
                                    }
                                    .foregroundStyle(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    .background {
                                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                                            .fill(Color("AccentColor"))
                                    }
                                }
                                .zIndex(0)

                                GridRow {
                                    //                            if !editing {
                                    HStack {
                                        Label(localized: .localizable.correspondent, systemImage: "person.fill")
                                            .labelStyle(.iconOnly)
                                            .font(.title)

                                        if let id = document.correspondent, let name = store.correspondents[id]?.name {
                                            Text(name)
                                        } else {
                                            Text(.localizable.correspondentNotAssignedPicker)
                                        }
                                    }
                                    .matchedGeometryEffect(id: "Edit", in: animation, isSource: !editing)
                                    .foregroundStyle(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    .background {
                                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                                            .fill(.orange)
                                    }
                                    //                            .zIndex(editing ? 1 : 0)
                                    .zIndex(1)

                                    .onTapGesture {
//                                        withAnimation {
                                        editing = true
//                                        }
                                    }
                                    //                            }
                                    //                            else {
                                    ////                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                    //                                HStack {}
                                    //                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    //                            }

                                    HStack {
                                        Label(localized: .localizable.documentType, systemImage: "doc.fill")
                                            .labelStyle(.iconOnly)
                                            .font(.title)

                                        if let id = document.correspondent, let name = store.correspondents[id]?.name {
                                            Text(name)
                                        } else {
                                            Text(.localizable.correspondentNotAssignedPicker)
                                        }
                                    }
                                    .foregroundStyle(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    .background {
                                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                                            .fill(Color("AccentColor"))
                                    }
                                }

                                GridRow {
                                    Text("Other")
                                    Text("Stuff")
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
//                .transition(.opacity)
            }

            if editing {
                ScrollView(.vertical) {
                    Text("Edit UIx")
                    Button("Done") {
                        editing = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .safeAreaInset(edge: .top) {
                    VStack {
                        if editing {
//                                    SearchBarView(text: $text)
//                                        .matchedGeometryEffect(id: "Edit", in: animation, isSource: editing)
//                                        .background {
//                                            RoundedRectangle(cornerRadius: 25, style: .continuous)
//                                                .fill(.regularMaterial)
//                                                .stroke(Color.orange, lineWidth: 2)
//                                                .matchedGeometryEffect(id: "Edit", in: animation, isSource: false)
//                                        }
                            Text("Pick correspondent")
                                .matchedGeometryEffect(id: "Edit", in: animation, isSource: true)
                                .padding(.vertical)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.orange)
                                .background {
                                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                                        .fill(.regularMaterial)
                                        .stroke(Color.orange, lineWidth: 2)
                                        .shadow(color: Color("ImageShadow"), radius: 10)
                                }
                                .padding()
                                .onTapGesture {
                                    editing = false
                                }
                        }
                    }
                    .animation(editing ? .spring(duration: openDuration, bounce: 0.2) : .spring(duration: closeDuration, bounce: 0.2).delay(delay), value: editing)
                }
            }
        }
        .animation(.spring(duration: 0.2, bounce: 0.2), value: editing)
//        .animation(editing ? .spring(duration: openDuration, bounce: 0.2) : .spring(duration: closeDuration, bounce: 0.2).delay(delay), value: editing)

        .navigationBarTitleDisplayMode(.inline)

        .sheet(isPresented: $showPreviewSheet) {
            PreviewWrapper(state: $download, detent: $editDetent)
                .presentationDetents(Set(Self.editDetents), selection: $editDetent)
                .presentationBackgroundInteraction(
                    .enabled(upThrough: .medium)
                )
                .interactiveDismissDisabled()
        }

        .onChange(of: store.documents) {
            if let document = store.documents[document.id] {
                self.document = document
            }
        }

        .task {
            await loadDocument()
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {}
                }
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
