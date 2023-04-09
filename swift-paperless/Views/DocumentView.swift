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
        var chevron = true

        init(@ViewBuilder label: @escaping () -> Label,
             active: Bool,
             action: @escaping () -> Void,
             chevron: Bool = true)
        {
            self.label = label
            self.action = action
            self.active = active
            self.chevron = chevron
        }

        var body: some View {
            Button(action: action) {
                HStack {
                    label()
                    if chevron {
                        Image(systemName: "chevron.down")
                    }
                }
                .frame(minHeight: 25)
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
    @State private var filterState = FilterState()

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
                        Task { store.filterState = filterState }
                    }
                }
            }
        }
    }

    private struct CircleCounter: View {
        enum Mode {
            case include
            case exclude
        }

        var value: Int
        var mode = Mode.include

        private var color: Color {
            switch mode {
            case .include:
                return Color.accentColor
            case .exclude:
                return Color.red
            }
        }

        var body: some View {
            Text("\(value)")
                .foregroundColor(.white)
                .if(value == 1) { view in view.padding(5).padding(.leading, -1) }
                .if(value > 1) { view in view.padding(5) }
                .frame(minWidth: 20, minHeight: 20)
                .background(Circle().fill(color))
        }
    }

    private enum Aspect {
        case tag
        case correspondent
        case documentType
    }

    private func present(_ aspect: Aspect) {
        Task {
            // needed to unblock opening when menu is open
            try? await Task.sleep(for: .seconds(0.05))
            switch aspect {
            case .tag:
                showDocumentType = false
                showCorrespondent = false
                showTags = true
            case .correspondent:
                showDocumentType = false
                showCorrespondent = true
                showTags = false
            case .documentType:
                showDocumentType = true
                showCorrespondent = false
                showTags = false
            }
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                if filterState.filtering {
                    Menu {
                        Text("\(filterState.ruleCount) filter(s) applied")
                        Divider()
                        Button(role: .destructive) {
                            withAnimation {
                                store.filterState.clear()
                                filterState.clear()
                            }
                        } label: {
                            Label("Clear filters", systemImage: "xmark")
                        }
                    } label: {
                        Element(label: {
                            Label("Filtering", systemImage: "line.3.horizontal.decrease")
                                .labelStyle(.iconOnly)
                            CircleCounter(value: filterState.ruleCount)
                        }, active: true, action: {}, chevron: false)
//                    } primaryAction: {
//                        withAnimation {
//                            store.filterState.clear()
//                            filterState.clear()
//                        }
                    }
                }

                Element(label: {
                    switch filterState.tags {
                    case .any:
                        Text("Tags")
                    case .notAssigned:
                        Text("None")
                    case .allOf(let include, let exclude):
                        let count = include.count + exclude.count
                        if count == 1 {
                            if let i = include.first, let name = store.tags[i]?.name {
                                Text(name)
                            }
                            else if let i = exclude.first, let name = store.tags[i]?.name {
                                Label("Exclude", systemImage: "xmark")
                                    .labelStyle(.iconOnly)
                                Text("\(name)")
                            }
                            else {
                                Text("1 tag")
                                    .redacted(reason: .placeholder)
                            }
                        }
                        else {
                            if !include.isEmpty, !exclude.isEmpty {
                                CircleCounter(value: include.count, mode: .include)
                                Text("/")
                                CircleCounter(value: exclude.count, mode: .exclude)
                            }
                            else if !include.isEmpty {
                                CircleCounter(value: count, mode: .include)
                            }
                            else {
                                CircleCounter(value: count, mode: .exclude)
                            }
                            Text("Tags")
                        }
                    case .anyOf(let ids):
                        if ids.count == 1 {
                            if let name = store.tags[ids.first!]?.name {
                                Text(name)
                            }
                            else {
                                Text("1 tag")
                                    .redacted(reason: .placeholder)
                            }
                        }
                        else {
                            CircleCounter(value: ids.count)
                            Text("Tags")
                        }
                    }
                }, active: filterState.tags != .any) { present(.tag) }

                Element(label: {
                    switch filterState.documentType {
                    case .any:
                        Text("Document Type")
                    case .notAssigned:
                        Text("None")
                    case .only(let id):
                        if let name = store.documentTypes[id]?.name {
                            Text(name)
                        }
                        else {
                            Text("1 document type")
                                .redacted(reason: .placeholder)
                        }
                    }
                }, active: filterState.documentType != .any) { present(.documentType) }

                Element(label: {
                    switch filterState.correspondent {
                    case .any:
                        Text("Correspondent")
                    case .notAssigned:
                        Text("None")
                    case .only(let id):
                        if let name = store.correspondents[id]?.name {
                            Text(name)
                        }
                        else {
                            Text("1 correspondent")
                                .redacted(reason: .placeholder)
                        }
                    }
                }, active: filterState.correspondent != .any) { present(.correspondent) }

                Divider()

                Element(label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                }, active: false, action: {})

                Spacer()
            }
            .padding(.horizontal)
            .foregroundColor(.primary)
        }
        .task {
            filterState = store.filterState
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
                TagFilterView(
                    selectedTags: $filterState.tags)
            }
        }

        .sheet(isPresented: $showDocumentType) {
            modal($showDocumentType, title: "Document Type") {
                CommonPicker(
                    selection: $filterState.documentType,
                    elements: store.documentTypes.sorted {
                        $0.value.name < $1.value.name
                    }.map { ($0.value.id, $0.value.name) }
                )
            }
        }

        .sheet(isPresented: $showCorrespondent) {
            modal($showCorrespondent, title: "Correspondent") {
                CommonPicker(
                    selection: $filterState.correspondent,
                    elements: store.correspondents.sorted {
                        $0.value.name < $1.value.name
                    }.map { ($0.value.id, $0.value.name) }
                )
            }
        }

        .onChange(of: store.filterState) { value in
            withAnimation {
                filterState = value
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

    @StateObject private var searchDebounce = DebounceObject(delay: 0.4)
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
    @State private var error: String?

    // This is intentionally NOT a StateObject because that stutters
    @State private var scrollOffset = ThrottleObject(value: CGPoint(), delay: 0.5)

    func load(clear: Bool) async {
        if clear {
            _ = withAnimation {
                Task { await store.fetchAll() }
            }
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

    func cell(document: Document) -> some View {
        Group {
            NavigationLink(value:
                NavigationState.detail(document: document)
            ) {
                DocumentCell(document: document, store: store)
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

    @State private var logoVisible = true

    var body: some View {
        NavigationStack(path: $nav.path) {
            VStack {
                SearchBarView(text: $searchDebounce.text, cancelEnabled: false) {
                    store.filterState.search = .init(
                        mode: .titleContent,
                        text: searchDebounce.debouncedText
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                FilterBar()
                GeometryReader { geo in
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
                        .frame(width: geo.size.width)
                    }
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Group {
                        if isLoading {
                            ProgressView()
                                .transition(.scale)
                        }
                    }
                }
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

            .onChange(of: store.documents) { _ in
                documents = documents.compactMap { store.documents[$0.id] }
            }

            .onReceive(store.filterStatePublisher) { value in
                print("Filter updated \(value)")
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
                store.filterState.search = .init(
                    mode: .titleContent,
                    text: searchDebounce.debouncedText
                )
            }

            .task {
                if initialLoad {
                    isLoading = true
                    await load(clear: true)
                    isLoading = false
                    initialLoad = false
                }

                if let text = store.filterState.search.text {
                    searchDebounce.text = text
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
                DocumentCell(document: document, store: store)
                    .padding()
            }
            Spacer()
        }
        .task {
            documents = await store.fetchDocuments(clear: false)
        }
    }
}
