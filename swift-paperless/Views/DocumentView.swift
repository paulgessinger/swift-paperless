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

struct DocumentView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var connectionManager: ConnectionManager

    @StateObject private var searchDebounce = DebounceObject(delay: 0.1)
    @StateObject private var nav = NavigationCoordinator()

    @State private var documents: [Document] = []
    @State private var showFilterModal = false
    @State private var searchSuggestions: [String] = []
    @State private var initialLoad = true
    @State private var isLoading = false
    @State private var loadingMore = false
    @State private var filterState = FilterState()
    @State private var refreshRequested = false
    @State private var showFileImporter = false
    @State var showCreateModal = false
    @State var importUrl: URL?
    @State private var scrollOffset = ThrottleObject(value: CGPoint(), delay: 0.1)
    @State private var error: String?

    func load(clear: Bool) async {
        if clear {
            await store.fetchAll()
        }
        let new = await store.fetchDocuments(clear: clear)

        if clear {
            withAnimation {
                documents = new
            }
        }
        else {
            withAnimation {
                documents += new
            }
        }
    }

    func updateSearchCompletion() async {
        if searchDebounce.debouncedText == "" {
            searchSuggestions = []
        }
        else {
            searchSuggestions = await store.repository.getSearchCompletion(term: searchDebounce.debouncedText, limit: 10)
        }
    }

    func handleSearch(query: String) async {
        var filterState = store.filterState
        filterState.searchText = query == "" ? nil : query
        store.filterState = filterState

        isLoading = true
        await load(clear: true)
        isLoading = false
    }

    func cell(document: Document) -> some View {
        Group {
            NavigationLink(value:
                NavigationState.detail(document: document)
            ) {
                DocumentCell(document: document)
                    .contentShape(Rectangle())
            }

            .buttonStyle(.plain)
            .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))

            if document != documents.last {
                Divider()
                    .padding(.horizontal)
            }
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

    var body: some View {
        NavigationStack(path: $nav.path) {
            ZStack(alignment: .bottomTrailing) {
                OffsetObservingScrollView(offset: $scrollOffset.value) {
                    VStack(alignment: .leading) {
                        ForEach(documents.prefix(100).compactMap { store.documents[$0.id] }) { document in
                            cell(document: document)
                        }
                        LazyVStack(alignment: .leading) {
                            ForEach(documents.dropFirst(100).compactMap { store.documents[$0.id] }) { document in
                                cell(document: document)
                                    .task {
                                        let hasMore = await store.hasMoreDocuments()
                                        print("Check more: has: \(hasMore), #doc \(documents.count)")
                                        if let index = documents.firstIndex(where: { $0 == document }) {
                                            if index >= documents.count - 10 && !loadingMore && hasMore {
                                                print("LOAD MORE")
                                                Task {
                                                    loadingMore = true
                                                    await load(clear: false)
                                                    loadingMore = false
                                                }
                                            }
                                        }
                                    }
                            }
                        }

                        if !isLoading && !initialLoad {
                            Divider().padding()
                            HStack {
                                Spacer()
                                let text = (documents.isEmpty ? "No documents" : (documents.count == 1 ? "1 document" : "\(documents.count) documents")) + " found"
                                Text(text)
                                    .foregroundColor(.gray)
                                    .transition(.opacity)
                                Spacer()
                            }
                        }
                    }
                }

                .navigationDestination(for: NavigationState.self,
                                       destination: navigationDestinations)

                .refreshable {
                    // @TODO: Refresh animation here is broken if this modifies state that triggers rerender
                    if isLoading { return }
                    refreshRequested = true
                }

                // Decoupled refresh when scroll is back
                .onReceive(scrollOffset.publisher) { offset in
                    if offset.y >= -0.0 && refreshRequested {
                        refreshRequested = false
                        Task {
                            isLoading = true
                            await load(clear: true)
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
                    ToolbarItem(placement: .navigationBarLeading) {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .transition(.scale)
                            }
                        }
                    }
                }
                .navigationTitle("Documents")

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

                .onChange(of: store.documents) { _ in
                    documents = documents.compactMap { store.documents[$0.id] }
                }

                .onChange(of: store.filterState) { _ in
                    print("Filter updated \(store.filterState)")
                    Task {
                        // wait for a short bit while the modal is still
                        // open to let the animation finish
                        if showFilterModal {
                            do { try await Task.sleep(for: .seconds(0.5)) } catch {}
                        }
                        await load(clear: true)
                    }
                }

                .onChange(of: searchDebounce.debouncedText) { _ in
                    Task {
                        await updateSearchCompletion()

                        print("Change search to \(searchDebounce.debouncedText)")

                        if searchDebounce.debouncedText == "" {
                            store.filterState.searchText = nil
                            await load(clear: true)
                        }
                    }
                }

                Button(action: {
                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                    impactMed.impactOccurred()

                    showFilterModal.toggle()

                }) {
                    Label(title: { Text("Filter") }, icon: {
                        Image(systemName: store.filterState.filtering ?
                            "line.3.horizontal.decrease.circle.fill" :
                            "line.3.horizontal.decrease.circle"
                        )
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                    })
                    .labelStyle(.iconOnly)
                    .modifier(PillButton())
                }
                .padding()
            }

            .task {
                if initialLoad {
                    isLoading = true
                    await load(clear: true)
                    isLoading = false
                    initialLoad = false
                }
            }

            .searchable(text: $searchDebounce.text,
                        placement: .automatic)
            {
                ForEach(searchSuggestions, id: \.self) { v in
                    Text(v).searchCompletion(v)
                }
            }

            .onSubmit(of: .search) {
                print("Search submit: \(searchDebounce.text)")
                if searchDebounce.text == store.filterState.searchText {
                    return
                }
                Task {
                    store.filterState.searchText = searchDebounce.text
                    await load(clear: true)
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
