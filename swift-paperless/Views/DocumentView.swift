//
//  ContentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Combine
import os
import QuickLook
import SwiftUI

import AsyncAlgorithms

enum NavigationState: Equatable, Hashable {
    case root
    case detail(document: Document)
    case settings
}

class NavigationCoordinator: ObservableObject {
    @Published var path = NavigationPath()

    func popToRoot() {
        path.removeLast(path.count)
    }
}

struct TaskActivityToolbar: View {
    @EnvironmentObject var store: DocumentStore

    @State private var number: Int?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .overlay {
                if let number, number > 0 {
                    Menu {
                        ForEach(store.activeTasks.filter { $0.status == .STARTED }, id: \.id) { task in
                            let name = (task.taskFileName ?? task.taskName) ?? "unknown task"
                            Text("Processing \(name)")
                        }
                        let queued = store.activeTasks.filter { $0.status != .STARTED }.count
                        if queued > 0 {
                            Divider()
                            Text("\(queued) pending task(s)")
                        }
                    } label: {
                        TaskActivityView(text: "\(number)")
                    }
                }
            }
            .task {
                repeat {
                    Logger.shared.trace("Loading tasks")

                    // @TODO: Improve backend API to allow fetching only active:
//                https://github.com/paperless-ngx/paperless-ngx/blob/83f9f2d3870556a8f55167cbc89375fc967965a8/src/documents/views.py#L1072
                    await store.fetchTasks()

                    try? await Task.sleep(for: .seconds(10))
                }
                while !Task.isCancelled
            }

            .onChange(of: store.activeTasks) { _ in
                withAnimation {
                    number = store.activeTasks.count
                }
            }
    }
}

struct DocumentView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var connectionManager: ConnectionManager

    // MARK: State

    @StateObject private var searchDebounce = DebounceObject(delay: 0.4)
    @StateObject private var nav = NavigationCoordinator()

    @State private var documents: [Document] = []
    @State private var searchSuggestions: [String] = []
    @State private var initialLoad = true
    @State private var isLoading = false
    @State private var filterState = FilterState()
    @State private var refreshRequested = false
    @State private var showFileImporter = false
    @State var showCreateModal = false
    @State var importUrl: URL?
    @State private var error: String?
    @State private var logoutRequested = false

    @State private var dataScannerIsAvailable = false
    @State private var showDataScanner = false

    func load() async {
        let d = 0.3
        async let delay: () = Task.sleep(for: .seconds(d))
        withAnimation(.linear(duration: d)) {
            isLoading = true
        }
        Task { await store.fetchAll() }
        documents = []

        let new = await store.fetchDocuments(clear: true, pageSize: 21)

        documents = new
        try? await delay
        withAnimation {
            isLoading = false
        }
        initialLoad = false
    }

    func reload() async {
        Task { await store.fetchAll() }
        let new = await store.fetchDocuments(clear: true, pageSize: 21)

        withAnimation {
            documents = new
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
            SettingsView()
        default:
            fatalError()
        }
    }

    // MARK: Main View Body

    var body: some View {
        NavigationStack(path: $nav.path) {
            ScrollView(.vertical) {
                VStack {
                    if isLoading {
                        LoadingDocumentList()
                            .opacity(0.7)
                    }
                    else if !documents.isEmpty {
                        DocumentList(documents: $documents)
                    }
                    else if !initialLoad {
                        Text("No documents")
                            .padding(.vertical, 50)
                    }
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity)
            }

            .layoutPriority(1)

            .refreshable {
                if isLoading { return }
                Task { await reload() }
            }

            .safeAreaInset(edge: .top) {
                VStack {
                    SearchBarView(text: $store.filterState.searchText, cancelEnabled: false) {}
                        .padding(.horizontal)

                    FilterBar()
                        .padding(.bottom, 3)
                }

                .background(
                    Rectangle()
                        .fill(
                            Material.bar
                        )
                        .ignoresSafeArea(.container, edges: .top)
                )

                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.gray)
                        .frame(height: 1, alignment: .bottom)
                }
            }

            .toolbarBackground(.hidden, for: .navigationBar)

            .navigationDestination(for: NavigationState.self,
                                   destination: navigationDestinations)

            // MARK: Main toolbar

            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    TaskActivityToolbar()
                }
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

                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        NavigationLink(value: NavigationState.settings) {
                            Label("Settings", systemImage: "gear")
                        }

                        Divider()

                        Button(role: .destructive) {
                            logoutRequested = true
                        } label: {
                            Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                        }

                    } label: {
                        Label(String(localized: "Menu of more options", comment: "'More' menu"), systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }

                if dataScannerIsAvailable {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            Task {
                                try? await Task.sleep(for: .seconds(0.1))
                                showDataScanner = true
                            }
                        } label: {
                            Label("document_view.toolbar.asn", systemImage: "number.circle")
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)

            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.pdf],
                          allowsMultipleSelection: false,
                          onCompletion: importFile)

            .sheet(isPresented: $showCreateModal, onDismiss: {}) {
                CreateDocumentView(
                    sourceUrl: importUrl!,
                    callback: {
                        showCreateModal = false
                        Task { await store.fetchTasks() }
                    },
                    title: {
                        Text("Add document")
                    }
                )
                .environmentObject(store)
            }

            .sheet(isPresented: $showDataScanner, onDismiss: {}) {
                DataScannerView()
            }

            .alert(error ?? "", isPresented: Binding<Bool>(get: { error != nil }, set: {
                value in
                if !value {
                    error = nil
                }
            })) {}

            .confirmationDialog(String(localized: "Are you sure?", comment: "Logout confirmation"), isPresented: $logoutRequested, titleVisibility: .visible) {
                Button("Logout", role: .destructive) {
                    connectionManager.logout()
                }
                Button("Cancel", role: .cancel) {}
            }

            .onReceive(store.filterStatePublisher) { value in
                print("Filter updated \(value)")
                Task { await load() }
            }

            .onChange(of: store.documents) { _ in
                documents = documents.compactMap { store.documents[$0.id] }
            }

            .task {
                dataScannerIsAvailable = await DataScannerView.isAvailable
            }
        }
        .environmentObject(nav)
    }
}

// - MARK: Previews

private struct StoreHelper<Content>: View where Content: View {
    @ViewBuilder var content: () -> Content

    @StateObject var store = DocumentStore(repository: PreviewRepository())

    var body: some View {
        content()
            .environmentObject(store)
    }
}

struct DocumentView_Previews: PreviewProvider {
    static let store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        StoreHelper {
            DocumentView()
        }
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
            try? await Task.sleep(for: .seconds(0.1))
            documents = await store.fetchDocuments(clear: false)
            print("GOGOGO")
        }
    }
}
