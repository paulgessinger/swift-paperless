//
//  DocumentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Combine
import os
import PhotosUI
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

@MainActor
struct DocumentView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var filterModel: FilterModel
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var errorController: ErrorController

    // MARK: State

    @StateObject private var searchDebounce = DebounceObject(delay: 0.4)
    @State private var navPath = NavigationPath()

    @State private var searchSuggestions: [String] = []
    @State private var initialLoad = true
    @State private var isLoading = false
    @State private var refreshRequested = false
    @State private var showFileImporter = false
    @State private var isDocumentScannerAvailable = false
    @State private var showDocumentScanner = false
    @State private var showCreateModal = false
    @State private var importUrls: [URL] = []
    @State private var totalUrls = 0
    @State private var logoutRequested = false

    @State private var showPhotosPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    @State private var showDataScanner = false
    @State private var showTypeAsn = false

    // @TODO: Separate view model which does the copying on a background thread
    func importFile(result: [URL], isSecurityScoped: Bool) {
        do {
            showFileImporter = false
            showDocumentScanner = false

            var images: [UIImage] = []

            for selectedFile in result {
                if isSecurityScoped {
                    if selectedFile.startAccessingSecurityScopedResource() {
                        defer { selectedFile.stopAccessingSecurityScopedResource() }

                        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                        let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(selectedFile.lastPathComponent)

                        if FileManager.default.fileExists(atPath: temporaryFileURL.path) {
                            try FileManager.default.removeItem(at: temporaryFileURL)
                        }

                        // Try to find out what we got
                        guard let typeID = try selectedFile.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier, let supertypes = UTType(typeID)?.supertypes else {
                            Logger.shared.error("Unable to get structured type info for imported file")
                            errorController.push(message: String(localized: .localizable.errorDefaultMessage))
                            return
                        }

                        Logger.shared.debug("Have structured type info: \(supertypes)")
                        if supertypes.contains(.image) {
                            Logger.shared.debug("Have image")
                            let data = try Data(contentsOf: selectedFile)
                            if let image = UIImage(data: data) {
                                images.append(image)
                            } else {
                                Logger.shared.error("Could not load image from: \(selectedFile)")
                            }
                        } else {
                            Logger.shared.debug("Have PDF -> copy file ")
                            try FileManager.default.copyItem(at: selectedFile, to: temporaryFileURL)
                            importUrls.append(temporaryFileURL)
                            totalUrls += 1
                        }

                    } else {
                        Logger.shared.error("Document import: Access denied")
                        errorController.push(message: String(localized: .localizable.errorDefaultMessage))
                    }
                } else {
                    importUrls.append(selectedFile)
                    totalUrls += 1
                }
            }

            if !images.isEmpty {
                let pdf = try createPDFFrom(images: images)
                importUrls.append(pdf)
                totalUrls += 1
            }

            showCreateModal = true
        } catch {
            // Handle failure.
            Logger.shared.error("Unable to read file contents: \(error)")
            errorController.push(error: error)
        }
    }

    private func createCallback() {
        Task { await store.fetchTasks() }
        if !importUrls.isEmpty {
            importUrls.removeFirst()
        }
        if importUrls.isEmpty {
            showCreateModal = false
            totalUrls = 0
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

    private var savedViewNavigationTitle: String {
        guard let id = filterModel.filterState.savedView else {
            // No saved view active
            return String(localized: .localizable.documents)
        }
        guard let savedView = store.savedViews[id] else {
            // Not necessarily an error, might be still loading
            return String(localized: .localizable.documents)
        }
        if filterModel.filterState.modified {
            return String(localized: .localizable.savedViewModified(savedView.name))
        } else {
            return savedView.name
        }
    }

    private var createDocumentTitle: String {
        let remaining = totalUrls - importUrls.count + 1
        if totalUrls > 1 {
            return "\(String(localized: .localizable.documentAdd)) (\(remaining) / \(totalUrls))"
        } else {
            return String(localized: .localizable.documentAdd)
        }
    }

    // MARK: Main View Body

    var body: some View {
        NavigationStack(path: $navPath) {
            DocumentList(store: store, navPath: $navPath,
                         filterModel: filterModel,
                         errorController: errorController)

                .safeAreaInset(edge: .top) {
                    VStack {
                        SearchBarView(text: $filterModel.filterState.searchText, cancelEnabled: false) {}
                            .padding(.horizontal)

                        FilterBar()
                            .padding(.bottom, 3)
                            .opacity(filterModel.ready ? 1.0 : 0.0)
                            .animation(.default, value: filterModel.ready)
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

                .toolbarTitleMenu {
                    if !store.savedViews.isEmpty {
                        Button {
                            withAnimation {
                                filterModel.filterState.clear()
                            }
                        } label: {
                            Text(.localizable.allDocuments)
                        }
                        Divider()
                        ForEach(store.savedViews.map(\.value).sorted { $0.name < $1.name }.filter { $0.id != filterModel.filterState.savedView }, id: \.id) { savedView in
                            Button {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    withAnimation {
                                        filterModel.filterState = .init(savedView: savedView)
                                    }
                                }
                            } label: {
                                Text(savedView.name)
                            }
                        }
                    }
                }

                .navigationTitle(savedViewNavigationTitle)

                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        HStack {
                            TaskActivityToolbar()

                            Menu {
                                if isDocumentScannerAvailable {
                                    Button {
                                        showDocumentScanner = true
                                    } label: {
                                        Label(String(localized: .localizable.scanDocument), systemImage: "doc.viewfinder")
                                    }
                                }

                                Button {
                                    showFileImporter = true
                                } label: {
                                    Label(String(localized: .localizable.importDocument), systemImage: "folder.badge.plus")
                                }

                                Button {
                                    showPhotosPicker = true
                                } label: {
                                    Label(String(localized: .localizable.importPhotos), systemImage: "photo")
                                }
                            } label: {
                                Label(String(localized: .localizable.add), systemImage: "plus")
                            }
                        }
                    }

                    ToolbarItemGroup(placement: .navigationBarLeading) {
                        Menu {
                            NavigationLink(value: NavigationState.settings) {
                                Label(String(localized: .settings.title), systemImage: "gear")
                            }

                            ConnectionQuickChangeMenu()

                            #if DEBUG
                                Section("Debug") {
                                    Button("Trigger error without details") {
                                        errorController.push(message: "An error", details: nil)
                                    }
                                    Button("Trigger error with details") {
                                        errorController.push(message: "An error", details: "Some details")
                                    }
                                }
                            #endif

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
                              allowedContentTypes: [.pdf, .image],
                              allowsMultipleSelection: true,
                              onCompletion: { result in
                                  switch result {
                                  case let .success(urls):
                                      importFile(result: urls, isSecurityScoped: true)
                                  case let .failure(failure):
                                      errorController.push(error: failure)
                                  }
                              })

                .fullScreenCover(isPresented: $showDocumentScanner) {
                    DocumentScannerView(isPresented: $showDocumentScanner, onCompletion: { result in
                        Task {
                            switch result {
                            case let .success(urls):
                                await importFile(result: urls, isSecurityScoped: false)
                            case let .failure(failure):
                                await errorController.push(error: failure)
                            }
                        }
                    })
                    .ignoresSafeArea()
                }

                .sheet(isPresented: $showCreateModal, onDismiss: {
                    importUrls = []
                    totalUrls = 0
                }) {
                    if let url = importUrls.first {
                        CreateDocumentView(
                            sourceUrl: url,
                            callback: createCallback,
                            title: createDocumentTitle
                        )
                        .id(url)
                        .environmentObject(store)
                    }
                }

                .sheet(isPresented: $showDataScanner, onDismiss: {}) {
                    DataScannerView()
                }

                .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotos)

                .onChange(of: selectedPhotos) { _ in
                    Logger.shared.info("Photo picker returns \(selectedPhotos.count) photos")
                    guard !selectedPhotos.isEmpty else {
                        Logger.shared.debug("No photos, nothing to do")
                        return
                    }

                    Task {
                        do {
                            let url = try await createPDFFrom(photos: selectedPhotos)
                            importFile(result: [url], isSecurityScoped: false)
                        } catch {
                            Logger.shared.error("Got error when creating PDF from photos: \(error)")
                            errorController.push(error: error)
                        }
                    }
                }

                .confirmationDialog(String(localized: .localizable.confirmationPromptTitle), isPresented: $logoutRequested, titleVisibility: .visible) {
                    Button(String(localized: .localizable.logout), role: .destructive) {
                        connectionManager.logout()
                    }
                    Button(String(localized: .localizable.cancel), role: .cancel) {}
                }

                .task {
                    do {
                        async let fetch: Void = store.fetchAll()

                        isDocumentScannerAvailable = await DocumentScannerView.isAvailable

                        try await fetch
                    } catch {
                        errorController.push(error: error)
                    }
                }
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
