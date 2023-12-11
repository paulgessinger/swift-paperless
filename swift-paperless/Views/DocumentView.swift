//
//  DocumentView.swift
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

extension NavigationPath {
    mutating func popToRoot() {
        removeLast(count)
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
                            Text(.localizable.tasksProcessing(name))
                        }
                        let queued = store.activeTasks.filter { $0.status != .STARTED }.count
                        if queued > 0 {
                            Divider()
                            Text(.localizable.tasksPending(UInt(queued)))
                        }
                    } label: {
                        TaskActivityView(text: "\(number)")
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal)

            .task {
                repeat {
                    Logger.shared.trace("Loading tasks")

                    // @TODO: Improve backend API to allow fetching only active:
//                https://github.com/paperless-ngx/paperless-ngx/blob/83f9f2d3870556a8f55167cbc89375fc967965a8/src/documents/views.py#L1072
                    await store.fetchTasks()

                    try? await Task.sleep(for: .seconds(10))
                } while !Task.isCancelled
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
    @EnvironmentObject private var filterModel: FilterModel
    @EnvironmentObject private var connectionManager: ConnectionManager

    // MARK: State

    @StateObject private var searchDebounce = DebounceObject(delay: 0.4)
    @State private var navPath = NavigationPath()

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

    @State private var showDataScanner = false
    @State private var showTypeAsn = false

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
            } else {
                print("Access denied")
                error = "Cannot access selected file"
                // Handle denied access
            }
        } catch {
            // Handle failure.
            print("Unable to read file contents")
            print(error.localizedDescription)
            self.error = "Unable to read file contents: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    func navigationDestinations(nav: NavigationState) -> some View {
        switch nav {
        case let .detail(doc):
            DocumentDetailView(document: doc, navPath: $navPath)
        case .settings:
            SettingsView()
        default:
            fatalError()
        }
    }

    // MARK: Main View Body

    var body: some View {
        NavigationStack(path: $navPath) {
            DocumentList(store: store, navPath: $navPath,
                         filterState: $filterModel.filterState)

                .layoutPriority(1)

                .safeAreaInset(edge: .top) {
                    VStack {
                        SearchBarView(text: $filterModel.filterState.searchText, cancelEnabled: false) {}
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

                .safeAreaInset(edge: .bottom) {
                    if showTypeAsn {
                        TypeAsnView { document in
                            navPath.append(NavigationState.detail(document: document))
                            withAnimation {
                                showTypeAsn = false
                            }
                        }
                        .transition(.move(edge: .bottom))
                    }
                }

                .toolbarBackground(.hidden, for: .navigationBar)

                .navigationDestination(for: NavigationState.self,
                                       destination: navigationDestinations)

                // MARK: Main toolbar

                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        TaskActivityToolbar()

                        Button {
                            showFileImporter = true
                        } label: {
                            Label(String(localized: .localizable.add), systemImage: "plus")
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        LogoView()
                    }
                    ToolbarItemGroup(placement: .navigationBarLeading) {
                        Menu {
                            NavigationLink(value: NavigationState.settings) {
                                Label(String(localized: .settings.title), systemImage: "gear")
                            }

                            Divider()

                            Button(role: .destructive) {
                                logoutRequested = true
                            } label: {
                                Label(String(localized: .localizable.logout), systemImage: "rectangle.portrait.and.arrow.right")
                            }

                        } label: {
                            Label(String(localized: .localizable.detailsMenuLabel), systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }

                        if DataScannerView.isAvailable {
                            Button {
                                Task {
                                    try? await Task.sleep(for: .seconds(0.1))
                                    showDataScanner = true
                                }
                            } label: {
                                Label(String(localized: .localizable.toolbarAsnButton), systemImage: "number.circle")
                            }
                        } else {
                            Button {
                                withAnimation(.spring(response: 0.5)) {
                                    showTypeAsn.toggle()
                                }
                            } label: {
                                Label(String(localized: .localizable.toolbarAsnButton), systemImage: "number.circle")
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
                            Text(.localizable.documentAdd)
                        }
                    )
                    .environmentObject(store)
                }

                .sheet(isPresented: $showDataScanner, onDismiss: {}) {
                    DataScannerView()
                }

                // @TODO: What was this for?
//                .alert(error ?? "", isPresented: Binding<Bool>(get: { error != nil }, set: {
//                    value in
//                    if !value {
//                        error = nil
//                    }
//                })) {}

                .confirmationDialog(String(localized: .localizable.confirmationPromptTitle), isPresented: $logoutRequested, titleVisibility: .visible) {
                    Button(String(localized: .localizable.logout), role: .destructive) {
                        connectionManager.logout()
                    }
                    Button(String(localized: .localizable.cancel), role: .cancel) {}
                }

                .task {
                    await store.fetchAll()
                }

//            .onChange(of: store.documents) { _ in
//                documents = documents.compactMap { store.documents[$0.id] }
//            }
        }
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

// @TODO: Fix this
private struct HelperView: View {
    @EnvironmentObject var store: DocumentStore
//    @State var documents = [Document]()
    @State var filterState = FilterState()

    var body: some View {
        VStack {
//            FilterBar()
//            ForEach(documents.prefix(5), id: \.id) { document in
//                DocumentCell(document: document)
//                    .padding()
//            }
//            Spacer()
        }
        .task {
            try? await Task.sleep(for: .seconds(0.1))
//            documents = await store.fetchDocuments(clear: false, filter: filterState)
            print("GOGOGO")
        }
    }
}
