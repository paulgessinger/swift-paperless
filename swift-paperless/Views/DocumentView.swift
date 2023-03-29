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

struct FilterBar: View {
    struct Element<Label: View>: View {
        var label: () -> Label
        var action: () -> Void
        var active: Bool

        init(@ViewBuilder label: @escaping () -> Label, active: Bool, action: @escaping () -> Void) {
            self.label = label
            self.action = action
            self.active = active
        }

        var body: some View {
            Button(action: action) {
                HStack {
                    label()
                    Image(systemName: "chevron.down")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(Color("ElementBackground"))
                }
                .overlay(
                    Capsule()
                        .strokeBorder(active ? Color.accentColor : Color("ElementBorder"),
                                      lineWidth: 1))
                .foregroundColor(active ? Color.accentColor : Color.primary)
            }
            .if(active) { view in view.bold() }
        }
    }

    @EnvironmentObject private var store: DocumentStore

    @State private var showTags = false
    @State private var showDocumentType = false
    @State private var showCorrespondent = false

    @ViewBuilder
    func modal<Content: View>(_ isPresented: Binding<Bool>, title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            VStack {
                content()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented.wrappedValue = false
                    }
                }
            }
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Element(label: {
                    switch store.filterState.tags {
                    case .any:
                        Text("Tags")
                    case .notAssigned:
                        Text("None")
                    case .only(let ids):
                        if ids.count == 1 {
                            Text(store.tags[ids[0]]?.name ?? "1 tag")
                        }
                        else {
                            Text("\(ids.count) tags")
                        }
                    }
                }, active: store.filterState.tags != .any) { showTags = true }

                Element(label: {
                    switch store.filterState.documentType {
                    case .any:
                        Text("Document Type")
                    case .notAssigned:
                        Text("None")
                    case .only(let id):
                        Text(store.documentTypes[id]?.name ?? "1 document type")
                    }
                }, active: store.filterState.documentType != .any) { showDocumentType = true }

                Element(label: {
                    switch store.filterState.correspondent {
                    case .any:
                        Text("Correspondent")
                    case .notAssigned:
                        Text("None")
                    case .only(let id):
                        Text(store.correspondents[id]?.name ?? "1 correspondent")
                    }
                }, active: store.filterState.correspondent != .any) { showCorrespondent = true }

                Spacer()
            }
            .padding(.horizontal)
            .foregroundColor(.primary)
        }
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .fill(Color("Divider"))
                .frame(maxWidth: .infinity, maxHeight: 1),
            alignment: .bottom
        )
        .padding(.bottom, -8)

        .sheet(isPresented: $showTags) {
            modal($showTags, title: "Tags") {
                TagSelectionView(tags: store.tags,
                                 selectedTags: $store.filterState.tags)
            }
        }

        .sheet(isPresented: $showDocumentType) {
            modal($showDocumentType, title: "Document Type") {
                CommonPicker(
                    selection: $store.filterState.documentType,
                    elements: store.documentTypes.sorted {
                        $0.value.name < $1.value.name
                    }.map { ($0.value.id, $0.value.name) }
                )
            }
        }

        .sheet(isPresented: $showCorrespondent) {
            modal($showCorrespondent, title: "Correspondent") {
                CommonPicker(
                    selection: $store.filterState.correspondent,
                    elements: store.correspondents.sorted {
                        $0.value.name < $1.value.name
                    }.map { ($0.value.id, $0.value.name) }
                )
            }
        }
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
            VStack {
                FilterBar()

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
                    .padding(.top, 8)
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
                        do { try await Task.sleep(for: .seconds(2.5)) } catch {}
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
