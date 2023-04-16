//
//  ContentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Combine
import QuickLook
import SwiftUI

import AsyncAlgorithms

struct SearchFilterBar<Content: View>: View {
    @Environment(\.isSearching) private var isSearching

    var content: () -> Content

    var body: some View {
        if isSearching {
            content()
        }
    }
}

struct PillButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 15)
            .padding(.vertical, 15)
            .foregroundColor(.white)
            .background(LinearGradient(colors: [
                    Color(uiColor: UIColor(Color("AccentColor")).ligher()),
                    Color.accentColor
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(Capsule())
            .shadow(radius: 5)
    }
}

enum NavigationState: Equatable, Hashable {
    case root
    case detail(document: Document)
    case settings
}

class NavigationCoordinator: ObservableObject {
    var path = NavigationPath()

    func popToRoot() {
        path.removeLast(path.count)
    }
}

private struct LoadingDocumentList: View {
    @State private var documents: [Document] = []
    @StateObject private var store = DocumentStore(repository: PreviewRepository())

    var body: some View {
        VStack {
            ForEach(documents, id: \.self) { document in
                DocumentCell(document: document)
                    .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
                    .redacted(reason: .placeholder)
                Divider()
                    .padding(.horizontal)
            }
        }
        .environmentObject(store)
        .task {
            documents = await store.fetchDocuments(clear: true, pageSize: 10)
//            documents = await PreviewRepository().documents(filter: FilterState()).fetch(limit: 10)
        }
    }
}

private struct DocumentList: View {
    @EnvironmentObject private var store: DocumentStore

    @Binding var documents: [Document]
    @State private var loadingMore = false

    private let stackCutoff = 100

    struct Cell: View {
        var document: Document

        var body: some View {
            NavigationLink(value:
                NavigationState.detail(document: document)
            ) {
                DocumentCell(document: document)
                    .contentShape(Rectangle())
            }

            .buttonStyle(.plain)
            .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))

//            if document != documents.last {
            Divider()
                .padding(.horizontal)
//            }
        }
    }

    func loadMore() async {
        let new = await store.fetchDocuments(clear: false, pageSize: 101)
        documents += new
    }

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(documents
                .prefix(stackCutoff)
                .compactMap { store.documents[$0.id] })
            { document in
                Cell(document: document)
//                    .if(document.id == documents.last?.id) { view in
//                        view.task {
//                            let hasMore = await store.hasMoreDocuments()
//                            print("Check more: has: \(hasMore), #doc \(documents.count)")
//                            if !loadingMore && hasMore {
//                                loadingMore = true
//                                await load(false)
//                                loadingMore = false
//                            }
//                        }
//                    }
            }

            LazyVStack(alignment: .leading) {
                let docs = documents
                    .dropFirst(stackCutoff)
                    .compactMap { store.documents[$0.id] }

                ForEach(
                    Array(zip(docs.indices, docs)), id: \.1.id
                ) { index, document in
                    Cell(document: document)
                        .if(index > docs.count - 10) { view in
                            view.task {
                                let hasMore = await store.hasMoreDocuments()
                                print("Check more: has: \(hasMore), #doc \(documents.count)")
                                if !loadingMore && hasMore {
                                    loadingMore = true
//                                    await load(false)
                                    await loadMore()
                                    loadingMore = false
                                }
                            }
                        }
                }
            }

//                    if !isLoading && !initialLoad {
//                        Divider().padding()
//                        HStack {
//                            Spacer()
//                            let text = (documents.isEmpty ? "No documents" : (documents.count == 1 ? "1 document" : "\(documents.count) documents")) + " found"
//                            Text(text)
//                                .foregroundColor(.gray)
//                                .transition(.opacity)
//                            Spacer()
//                        }
//                    }
        }
    }
}

struct DocumentView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var connectionManager: ConnectionManager

    @StateObject private var searchDebounce = DebounceObject(delay: 0.4)
    @StateObject private var nav = NavigationCoordinator()

    @State private var documents: [Document] = []
    @State private var showFilterModal = false
    @State private var searchSuggestions: [String] = []
    @State private var initialLoad = true
    @State private var isLoading = false
    @State private var filterState = FilterState()
    @State private var refreshRequested = false
    @State private var showFileImporter = false
    @State var showCreateModal = false
    @State var importUrl: URL?
    @State private var error: String?

//    @State private var searchFocused = false

    // This is intentionally NOT a StateObject because that stutters
    @State private var scrollOffset = ThrottleObject(value: CGPoint(), delay: 0.5)

    func load() async {
        withAnimation {
            isLoading = true
        }
        Task { await store.fetchAll() }
        documents = []
//        }

        let new = await store.fetchDocuments(clear: true, pageSize: 101)

        documents = new
        withAnimation {
            isLoading = false
        }
    }

    func importFile(result: Result<[URL], Error>) {
        do {
            guard let selectedFile: URL = try result.get().first else { return }
            if selectedFile.startAccessingSecurityScopedResource() {
                defer { selectedFile.stopAccessingSecurityScopedResource() }

                let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(selectedFile.lastPathComponent)

                if FileManager.default.fileExists(atPath: temporaryFileURL.path) {
                    try FileManager.default.removeItem(at: temporaryFileURL)
                }
                try FileManager.default.copyItem(at: selectedFile, to: temporaryFileURL)

                importUrl = temporaryFileURL
                showFileImporter = false
                showCreateModal = true
            }
            else {
                print("Access denied")
                error = "Cannot access selected file"
                // Handle denied access
            }
        }
        catch {
            // Handle failure.
            print("Unable to read file contents")
            print(error.localizedDescription)
            self.error = "Unable to read file contents: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    func navigationDestinations(nav: NavigationState) -> some View {
        switch nav {
        case .detail(let doc):
            DocumentDetailView(document: doc)
                .navigationBarTitleDisplayMode(.inline)
        case .settings:
            VStack {
                Label("Settings", systemImage: "gear")
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
            }
        default:
            fatalError()
        }
    }

    @State private var logoVisible = true

    var body: some View {
        NavigationStack(path: $nav.path) {
            VStack {
                SearchBarView(text: $store.filterState.searchText, cancelEnabled: false) {
//                    store.filterState.searchMode = .titleContent
//                    store.filterState.searchText = searchDebounce.debouncedText
                }
                .padding(.horizontal)
                .padding(.bottom, 4)

                FilterBar()

                GeometryReader { geo in
                    OffsetObservingScrollView(offset: $scrollOffset.value) {
                        if isLoading {
                            LoadingDocumentList()
                                .opacity(0.7)
                                .frame(width: geo.size.width)
                        }
                        else {
                            DocumentList(documents: $documents)
                        }
                    }
                    .padding(.top, 8)
                    .frame(width: geo.size.width)
                }
                .layoutPriority(1)
                .refreshable {
                    // @TODO: Refresh animation here is broken if this modifies state that triggers rerender
                    if isLoading { return }
                    refreshRequested = true
                }
            }

            .navigationDestination(for: NavigationState.self,
                                   destination: navigationDestinations)

            // Decoupled refresh when scroll is back
            .onReceive(scrollOffset.publisher) { offset in
                Task {
                    if logoVisible != (offset.y < 10) {
                        withAnimation { logoVisible.toggle() }
                    }
                }
                if offset.y >= -0.0 && refreshRequested {
                    refreshRequested = false
                    Task {
                        isLoading = true
                        await load()
                        isLoading = false
                    }
                }
            }

            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }

                ToolbarItem(placement: .principal) {
                    LogoView()
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            connectionManager.logout()
                        } label: {
                            Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                        }

                        NavigationLink(value: NavigationState.settings) {
                            Label("Settings", systemImage: "gear")
                        }

                    } label: {
                        Label("Menu", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }
//                ToolbarItem(placement: .navigationBarLeading) {
//                    Group {
//                        if isLoading {
//                            ProgressView()
//                                .transition(.scale)
//                        }
//                    }
//                }
            }
            .navigationBarTitleDisplayMode(.inline)

            .sheet(isPresented: $showFilterModal, onDismiss: {}) {
                FilterView()
                    .environmentObject(store)
            }

            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.pdf],
                          allowsMultipleSelection: false,
                          onCompletion: importFile)

            .sheet(isPresented: $showCreateModal, onDismiss: {}) {
                CreateDocumentView(
                    sourceUrl: importUrl!,
                    callback: {
                        showCreateModal = false
                    },
                    title: {
                        Text("Add document")
                    }
                )
                .environmentObject(store)
            }

            .alert(error ?? "", isPresented: Binding<Bool>(get: { error != nil }, set: {
                value in
                if !value {
                    error = nil
                }
            })) {}

            .onReceive(store.filterStatePublisher) { value in
                if initialLoad { return }
                print("Filter updated \(value)")
                Task {
                    // wait for a short bit while the modal is still
                    // open to let the animation finish
//                    if showFilterModal {
//                        do { try await Task.sleep(for: .seconds(0.5)) } catch {}
//                    }
//                    isLoading = true
                    await load()
//                    isLoading = false

//                    if !searchFocused {
//                        searchDebounce.text = value.searchText ?? ""
//                    }
                }
            }

//            .onChange(of: searchDebounce.debouncedText) { _ in
//                store.filterState.searchMode = .titleContent
//                store.filterState.searchText = searchDebounce.debouncedText
//            }

            .task {
                if initialLoad {
//                    if let text = store.filterState.searchText {
//                        searchDebounce.text = text
//                    }
//                    isLoading = true
                    await load()
//                    isLoading = false
                    initialLoad = false
                }
            }
        }
        .environmentObject(nav)
    }
}

struct DocumentView_Previews: PreviewProvider {
    static let store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        DocumentView()
            .environmentObject(store)
    }
}

struct FilterBar_Previews: PreviewProvider {
    static let store = DocumentStore(repository: PreviewRepository())
    static var previews: some View {
        HelperView()
            .environmentObject(store)
    }
}

private struct HelperView: View {
    @EnvironmentObject var store: DocumentStore
    @State var documents = [Document]()

    var body: some View {
        VStack {
            FilterBar()
            ForEach(documents.prefix(5), id: \.id) { document in
                DocumentCell(document: document)
                    .padding()
            }
            Spacer()
        }
        .task {
            documents = await store.fetchDocuments(clear: false)
        }
    }
}
