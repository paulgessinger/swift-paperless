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

enum NavigationState: Equatable, Hashable, Identifiable {
    case root
    case detail(document: Document)
    case settings
    case tasks
    case task(_: PaperlessTask)

    var id: UInt {
        switch self {
        case .root:
            1
        case .detail:
            2
        case .settings:
            3
        case .tasks:
            4
        case .task:
            5
        }
    }
}

extension NavigationPath {
    mutating func popToRoot() {
        removeLast(count)
    }
}

@MainActor
struct DocumentView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var errorController: ErrorController

    @StateObject private var filterModel = FilterModel()

    // MARK: State

    @StateObject private var searchDebounce = DebounceObject(delay: 0.4)
    @State private var navPath = NavigationPath()

    @State private var searchSuggestions: [String] = []
    @State private var initialLoad = true
    @State private var isLoading = false
    @State private var refreshRequested = false
    @State private var showFileImporter = false
    @State private var isDocumentScannerAvailable = false
    @State private var isDataScannerAvailable = false
    @State private var showDocumentScanner = false
    @State private var showCreateModal = false
    @State private var importUrls: [URL] = []
    @State private var totalUrls = 0
    @State private var logoutRequested = false

    @State private var showPhotosPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    @State private var showDataScanner = false
    @State private var showTypeAsn = false
    @State private var taskViewNavState: NavigationState? = nil

    // @TODO: Separate view model which does the copying on a background thread
    func importFile(result: [URL], isSecurityScoped: Bool) {
        Logger.shared.debug("Initiate import of \(result.count) URLs")
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            TaskActivityToolbar(navState: $taskViewNavState)

            Label(String(localized: .localizable.add), systemImage: "plus")
                .overlay {
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
                    } label: {}
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
                            errorController.push(message: "An error")
                        }
                        Button("Trigger error with details") {
                            errorController.push(message: "An error", details: "Some details")
                        }

                        Button("Trigger many errors") {
                            for i in 0 ..< 10 {
                                errorController.push(message: "Error no \(i)", details: i % 2 == 0 ? "Some details" : nil)
                            }
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

            if isDataScannerAvailable {
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

    // MARK: Main View Body

    var body: some View {
        NavigationStack(path: $navPath) {
            DocumentList(store: store, navPath: $navPath,
                         filterModel: filterModel,
                         errorController: errorController)

                .safeAreaInset(edge: .top) {
                    FilterAssembly(filterModel: filterModel)

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
                .navigationBarTitleDisplayMode(.inline)

                .toolbar {
                    toolbar
                }

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
                            Logger.shared.debug("Have PDF at \(url)")
                            importFile(result: [url], isSecurityScoped: false)
                            selectedPhotos = []
                        } catch {
                            Logger.shared.error("Got error when creating PDF from photos: \(error)")
                            errorController.push(error: error)
                        }
                    }
                }

                .sheet(item: $taskViewNavState, content: tasksSheet)

                .confirmationDialog(String(localized: .localizable.confirmationPromptTitle), isPresented: $logoutRequested, titleVisibility: .visible) {
                    Button(String(localized: .localizable.logout), role: .destructive) {
                        connectionManager.logout()
                    }
                    Button(String(localized: .localizable.cancel), role: .cancel) {}
                }

                .task {
                    do {
                        async let fetch: Void = store.fetchAll()

                        (isDataScannerAvailable, isDocumentScannerAvailable) = await (DataScannerView.isAvailable, DocumentScannerView.isAvailable)

                        try await fetch
                    } catch {
                        errorController.push(error: error)
                    }
                }
        }
        .environmentObject(filterModel)
    }

    private func tasksSheet(state: NavigationState) -> some View {
        var navPath = NavigationPath()
        switch state {
        case .task:
            navPath.append(state)
        case .tasks:
            break
        default:
            fatalError("Invalid task view navigation state pushed")
        }
        return TasksView(navPath: navPath)
            .errorOverlay(errorController: errorController, offset: 15)
    }
}

struct FilterAssembly: View {
    @ObservedObject var filterModel: FilterModel

    var body: some View {
        VStack {
            HStack {
                SearchBarView(text: $filterModel.filterState.searchText, cancelEnabled: false) {}

                Menu {
                    ForEach(FilterState.SearchMode.allCases, id: \.self) { searchMode in
                        if filterModel.filterState.searchMode == searchMode {
                            Label(searchMode.localizedName, systemImage: "checkmark")
                        } else {
                            Button(searchMode.localizedName) {
                                filterModel.filterState.searchMode = searchMode
                            }
                        }
                    }

                } label: {
                    Label("X", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
            }
            .padding(.horizontal)

            FilterBar()
                .padding(.bottom, 3)
        }
        .opacity(filterModel.ready ? 1.0 : 0.0)
        .animation(.default, value: filterModel.ready)
    }
}

// - MARK: Previews

private struct StoreHelper<Content>: View where Content: View {
    @ViewBuilder var content: () -> Content

    @StateObject var store = DocumentStore(repository: PreviewRepository())
    @StateObject var errorController = ErrorController()
    @StateObject var connectionManager = ConnectionManager()

    var body: some View {
        content()
            .environmentObject(store)
            .environmentObject(errorController)
            .environmentObject(connectionManager)
    }
}

private struct FilterModelHelper<Content>: View where Content: View {
    @ViewBuilder var content: (FilterModel) -> Content

    @StateObject var filterModel = FilterModel()

    var body: some View {
        content(filterModel)
            .environmentObject(filterModel)
    }
}

#Preview("DocumentView") {
    StoreHelper {
        DocumentView()
    }
}

#Preview("FilterBar") {
    StoreHelper {
        FilterModelHelper { filterModel in
            NavigationStack {
                ScrollView(.vertical) {
                    FilterAssembly(filterModel: filterModel)
                }
            }
        }
    }
}
