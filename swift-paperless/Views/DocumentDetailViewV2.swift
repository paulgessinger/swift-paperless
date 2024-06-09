//
//  DocumentDetailViewV2.swift
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

struct DocumentDetailViewV2: View {
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
    @State private var editDetentOnFocus: PresentationDetent? = nil

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
    @FocusState private var searchFocus: Bool

    private var editingView: some View {
        VStack {
            if editing {
                ScrollView(.vertical) {
                    VStack {
                        Text("Stuff")
                        Text("Stuff")
                        Text("Stuff")
                        Text("Stuff")
                        Text("Stuff")
                        Text("Stuff")
                        Text("Stuff")
                    }
                }
                .safeAreaInset(edge: .top, alignment: .center) {
                    VStack {
                        HStack {
                            Label(localized: .localizable.correspondent, systemImage: "person.fill")
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .matchedGeometryEffect(id: "EditIcon", in: animation, isSource: true)
                            Text(.localizable.correspondent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
//                        SearchBarView(text: $text)
                        HStack {
                            Label(String(localized: .localizable.search), systemImage: "magnifyingglass")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.white)
                                .padding(.trailing, -2)
                            TextField(text: $text) {
                                Text("Search")
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.alphabet)
                            .focused($searchFocus)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(.thinMaterial)
                        )
                        .padding(.top)
                    }
                    .padding()
                    .foregroundStyle(.white)
                    .overlay(alignment: .topTrailing) {
                        Label(localized: .localizable.done, systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.thinMaterial))
                            .padding(10)
                            .onTapGesture {
                                Task {
                                    if searchFocus {
                                        searchFocus = false
                                        try? await Task.sleep(for: .seconds(0.3))
                                    }
                                    editing = false
                                }
                            }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(.orange)
                    }
                    .matchedGeometryEffect(id: "Edit", in: animation, isSource: true)
                    .padding(.horizontal)
//
//                            GeometryReader { geo in
//                            }
//
//                                Label(localized: .localizable.done, systemImage: "xmark")
//                                    .labelStyle(.iconOnly)
//                                    .foregroundStyle(.primary)
//                                    .padding(10)
//                                    .background(Circle().fill(.thinMaterial))
//                                    .padding(10)
//                                    .onTapGesture { editing = false }
//
//                        }
                    ////                        .frame(height: 200)
//                        .padding()
//                    }
                }
                .task {
                    text = ""
                    try? await Task.sleep(for: .seconds(0.3))
                    searchFocus = true
                }
            }
        }
        .animation(.spring(duration: openDuration, bounce: 0.1), value: editing)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button {
                    searchFocus = false
                } label: {
                    Label(localized: .localizable.documentDetailPreviewTitle, systemImage: "keyboard.chevron.compact.down")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .onChange(of: searchFocus) {
            if searchFocus == true {
                editDetentOnFocus = editDetent
                editDetent = Self.editDetents.first!
            } else {
                if let editDetentOnFocus {
                    editDetent = editDetentOnFocus
                }
            }
        }
    }

    var body: some View {
        Group {
            editingView

            VStack {
                if !editing {
                    ScrollView(.vertical) {
                        VStack {
                            Grid {
                                Text(document.title)
                                    .font(.title)
                                    .bold()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .gridCellColumns(2)

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
                                //                                .zIndex(0)

                                GridRow {
//                                    if !editing {
                                    HStack {
                                        Label(localized: .localizable.correspondent, systemImage: "person.fill")
                                            .labelStyle(.iconOnly)
                                            .font(.title)
                                            .matchedGeometryEffect(id: "EditIcon", in: animation, isSource: true)
                                        Text("I am pretty long text here")
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .foregroundStyle(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    .background {
                                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                                            .fill(.orange)
                                            .matchedGeometryEffect(id: "Edit", in: animation, isSource: !editing)
                                    }

                                    .onTapGesture { editing = true }
//                                    }

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
                            .padding()
                        }
                    }
                }
            }
            .animation(.spring(duration: openDuration, bounce: 0.1), value: editing)
        }
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
                    DocumentDetailViewV2(document: document, navPath: $navPath)
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
