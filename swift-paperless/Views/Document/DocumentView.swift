//
//  DocumentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import AppShared
import Combine
import Common
import DataModel
import Networking
import Nuke
import Persistence
import PhotosUI
import SwiftUI
import os

enum NavigationState: Equatable, Hashable, Identifiable {
  case root
  case detail(document: Document)
  case tasks
  case task(_: PaperlessTask)

  var id: UInt {
    switch self {
    case .root: 1
    case .detail: 2
    case .tasks: 4
    case .task: 5
    }
  }
}

extension NavigationPath {
  mutating func popToRoot() {
    removeLast(count)
  }
}

// iPad-only: drives the saved-view sidebar selection.
enum SidebarSelection: Hashable {
  case allDocuments
  case savedView(UInt)
}

struct DocumentNotFoundError: DisplayableError {
  let id: UInt
  let connection: StoredConnection

  var message: String {
    String(localized: .app(.urlCallbackDocumentNotFoundTitle))
  }
  var details: String? {
    String(localized: .app(.urlCallbackDocumentNotFound(id, connection.label)))
  }
}

@MainActor
struct DocumentView: View {
  @Environment(DocumentStore.self) private var store
  @EnvironmentObject private var connectionManager: ConnectionManager
  @EnvironmentObject private var errorController: ErrorController
  @Environment(RouteManager.self) private var routeManager
  @Environment(NetworkMonitor.self) private var networkMonitor
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var filterModel = FilterModel()
  @State private var isFetching: Bool = false

  // MARK: State

  @State private var navPath: [NavigationState] = []

  // iPad split-view state. Compact size class ignores these.
  @State private var sidebarSelection: SidebarSelection? = .allDocuments
  @State private var selectedDocument: Document?
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  @State private var showFileImporter = false
  @State private var isDocumentScannerAvailable = false
  @State private var isDataScannerAvailable = false
  @State private var showDocumentScanner = false
  @State private var showCreateModal = false

  @StateObject private var importModel = DocumentImportModel()

  @State private var logoutRequested = false

  @State private var showPhotosPicker = false
  @State private var selectedPhotos: [PhotosPickerItem] = []

  @State private var showDataScanner = false
  @State private var taskViewNavState: NavigationState? = nil
  @Binding private var showSettings: Bool

  init(showSettings: Binding<Bool>) {
    _showSettings = showSettings
  }

  private func createCallback() {
    importModel.pop()
    if importModel.done {
      showCreateModal = false
      importModel.totalUrls = 0
    }
  }

  @ViewBuilder
  func navigationDestinations(nav: NavigationState) -> some View {
    switch nav {
    case .detail(let doc):
      DocumentDetailView(store: store, document: doc, navPath: $navPath)
    default:
      fatalError()
    }
  }

  private func handlePendingRoute() {
    guard let route = routeManager.pendingRoute else {
      return
    }

    func clear() async {
      if showDocumentScanner {
        showDocumentScanner = false
      }
      if !navPath.isEmpty {
        navPath.removeLast()
        guard (try? await Task.sleep(for: .seconds(0.5))) != nil else {
          return
        }
      }
    }

    Task {
      switch route.action {
      case .scan:
        routeManager.pendingRoute = nil
        Logger.shared.info("Opening document scanner from URL ")
        await clear()
        showDocumentScanner = true
      case .document(let id, _):
        Logger.shared.info("Opening document id \(id) from URL")
        do {

          guard case .document(let reqId, _) = route.action else { return }

          // Check if currently open id is the one that's requested
          if horizontalSizeClass == .regular {
            if selectedDocument?.id == reqId { return }
          } else {
            if let last = navPath.last {
              if case .detail(let open) = last {
                if reqId == open.id { return }
              }
            }
          }

          guard let document = try await store.document(id: id) else {
            Logger.shared.error("Document with id \(id) was not found")
            if let connId = connectionManager.activeConnectionId,
              let connection = connectionManager.connections[connId]
            {
              errorController.push(error: DocumentNotFoundError(id: id, connection: connection))
            }
            return
          }

          store.preloadThumbnail(for: document)
          if horizontalSizeClass == .regular {
            selectedDocument = document
          } else {
            await clear()
            navPath.append(NavigationState.detail(document: document))
          }
        }
      case .setFilter(let filter):
        routeManager.pendingRoute = nil
        Logger.shared.info("Setting filter from route")
        do {
          try applyRouteFilter(filter)
        } catch {
          errorController.push(error: error)
        }
      case .clearFilter:
        routeManager.pendingRoute = nil
        Logger.shared.info("Clearing filter in filter from route")
        filterModel.filterState.clear()

      default:
        break
      }
    }
  }

  private func applyRouteFilter(_ filter: Route.DeepLinkFilter) throws {
    var state = filterModel.filterState

    if let tags = filter.tags {
      state.tags = tags
    }
    if let correspondent = filter.correspondent {
      state.correspondent = correspondent
    }
    if let documentType = filter.documentType {
      state.documentType = documentType
    }
    if let storagePath = filter.storagePath {
      state.storagePath = storagePath
    }
    if let owner = filter.owner {
      state.owner = owner
    }
    if let searchText = filter.searchText {
      state.searchText = searchText
    }
    if let searchMode = filter.searchMode {
      state.searchMode = searchMode
    }
    if let asn = filter.asn {
      state.asn = asn
    }
    if let dateCreated = filter.dateCreated {
      try applyDateArgument(dateCreated, to: &state.date.created)
    }
    if let dateAdded = filter.dateAdded {
      try applyDateArgument(dateAdded, to: &state.date.added)
    }
    if let dateModified = filter.dateModified {
      if !store.repository.supports(feature: .dateFilterModified) {
        throw Route.ParseError.unsupportedModifiedDateFilter
      }
      try applyDateArgument(dateModified, to: &state.date.modified)
    }
    if let sortField = filter.sortField {
      state.sortField = sortField
    }
    if let sortOrder = filter.sortOrder {
      state.sortOrder = sortOrder
    }

    filterModel.filterState = state
  }

  private func applyDateArgument(
    _ argument: FilterState.DateFilter.Argument,
    to target: inout FilterState.DateFilter.Argument
  ) throws {
    if case .range(let range) = argument,
      !store.repository.supports(feature: .dateFilterPreviousIntervals)
    {
      switch range {
      case .previousWeek, .previousMonth, .previousQuarter, .previousYear:
        throw Route.ParseError.unsupportedPreviousIntervalDateFilter
      default:
        break
      }
    }

    target = argument
  }

  private var savedViewNavigationTitle: String {
    guard let id = filterModel.filterState.savedView else {
      // No saved view active
      return String(localized: .app(.documents))
    }
    guard let savedView = store.savedViews[id] else {
      // Not necessarily an error, might be still loading
      return String(localized: .app(.documents))
    }
    if filterModel.filterState.modified {
      return String(localized: .app(.savedViewModified(savedView.name)))
    } else {
      return savedView.name
    }
  }

  private var createDocumentTitle: String {
    if importModel.totalUrls > 1 {
      "\(String(localized: .app(.documentAdd))) (\(importModel.remaining) / \(importModel.totalUrls))"
    } else {
      String(localized: .app(.documentAdd))
    }
  }

  @ToolbarContentBuilder
  private var trailingToolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .navigationBarTrailing) {
      TaskActivityToolbar(navState: $taskViewNavState)

      Menu {
        Group {
          if isDocumentScannerAvailable {
            Button {
              showDocumentScanner = true
            } label: {
              Label(String(localized: .app(.scanDocument)), systemImage: "doc.viewfinder")
            }
          }

          Button {
            showFileImporter = true
          } label: {
            Label(
              String(localized: .app(.importDocument)), systemImage: "folder.badge.plus")
          }

          Button {
            showPhotosPicker = true
          } label: {
            Label(String(localized: .app(.importPhotos)), systemImage: "photo")
          }

        }
        .disabled(!store.permissions.test(.add, for: .document))

      } label: {
        Label(String(localized: .app(.add)), systemImage: "plus")
      }
      .tint(.accent)
    }
  }

  @ToolbarContentBuilder
  private var leadingToolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .navigationBarLeading) {
      Menu {

        Button {
          showSettings = true
        } label: {
          Label(String(localized: .settings(.title)), systemImage: "gear")
        }

        ConnectionQuickChangeMenu()

        // On iPad the ASN scanner moves into this menu — the leading
        // toolbar gets crowded next to the sidebar-toggle button when
        // the sidebar is collapsed, and there's no good place for a
        // separate ASN button.
        if horizontalSizeClass == .regular, isDataScannerAvailable {
          Button {
            showDataScanner = true
          } label: {
            Label(
              String(localized: .app(.toolbarAsnButton)),
              systemImage: "number.circle"
            )
          }
        }

        #if DEBUG
          Section("Debug") {
            Button("Trigger error without details") {
              errorController.push(message: "An error")
            }
            Button("Trigger error with details") {
              errorController.push(message: "An error", details: "Some details")
            }

            Button("Trigger many errors") {
              for i in 0..<10 {
                errorController.push(
                  message: "Error no \(i)", details: i % 2 == 0 ? "Some details" : nil)
              }
            }

            if let id = connectionManager.activeConnectionId {
              Button("Mark connection needs re-auth") {
                connectionManager.markNeedsAuth(for: id)
              }
            }

            Button(networkMonitor.debugForceOffline ? "Stop forcing offline" : "Force offline") {
              networkMonitor.debugForceOffline.toggle()
            }
          }
        #endif

        Divider()

        Button {
          logoutRequested = true
        } label: {
          Label(
            String(localized: .app(.logout)),
            systemImage: "rectangle.portrait.and.arrow.right"
          )
          .foregroundStyle(.red)
        }

      } label: {
        Label(String(localized: .app(.detailsMenuLabel)), systemImage: "ellipsis.circle")
          .labelStyle(.iconOnly)
      }
      .tint(.accent)

      .confirmationDialog(
        String(localized: .app(.confirmationPromptTitle)), isPresented: $logoutRequested,
        titleVisibility: .visible
      ) {
        Button(String(localized: .app(.logout)), role: .destructive) {
          connectionManager.logout(animated: true)
        }
      }

      if isDataScannerAvailable, horizontalSizeClass != .regular {
        Button {
          showDataScanner = true
        } label: {
          Label(String(localized: .app(.toolbarAsnButton)), systemImage: "number.circle")
        }
        .tint(.accent)
      }
    }
  }

  @ViewBuilder
  private var titleMenu: some View {
    if !store.savedViews.isEmpty {
      Button {
        withAnimation {
          filterModel.filterState.clear()
        }
      } label: {
        Text(.app(.allDocuments))
      }
    }

    Section(String(localized: .app(.savedViews))) {
      if store.permissions.test(.view, for: .savedView) {
        if !store.savedViews.isEmpty {
          ForEach(
            store.savedViews.map(\.value).sorted { $0.name < $1.name }.filter {
              $0.id != filterModel.filterState.savedView
            }, id: \.id
          ) { savedView in
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
        } else {
          Text(.app(.noSavedViews))
        }
      } else {
        Text(.permissions(.noViewPermissionsSavedViews))
      }
    }
  }

  // MARK: Filter assembly (shared compact + regular)

  @ViewBuilder
  private func filterAssemblyView(showsBackdrop: Bool) -> some View {
    if #available(iOS 26.0, *) {
      FilterAssembly(
        filterModel: filterModel, isFetching: isFetching, showsBackdrop: showsBackdrop)
    } else {
      FilterAssemblyiOS18(
        filterModel: filterModel, isFetching: isFetching, showsBackdrop: showsBackdrop)
    }
  }

  // MARK: Compact body (iPhone / compact size class)

  @ViewBuilder
  private var compactBody: some View {
    NavigationStack(path: $navPath) {
      DocumentList(
        store: store,
        onSelect: { navPath.append(.detail(document: $0)) },
        filterModel: filterModel,
        errorController: errorController,
        isFetching: $isFetching
      )

      .safeAreaInset(edge: .top) {
        filterAssemblyView(showsBackdrop: true)
      }

      .toolbarBackground(.hidden, for: .navigationBar)

      .navigationDestination(
        for: NavigationState.self,
        destination: navigationDestinations
      )

      // MARK: Main toolbar

      .toolbarTitleMenu {
        titleMenu
      }

      .navigationTitle(savedViewNavigationTitle)
      .navigationBarTitleDisplayMode(.inline)

      .toolbar {
        leadingToolbar
        trailingToolbar
      }
    }
  }

  // MARK: Regular body (iPad / regular size class)

  @ViewBuilder
  private var sidebarColumn: some View {
    List(selection: $sidebarSelection) {
      Section {
        NavigationLink(value: SidebarSelection.allDocuments) {
          Label(
            String(localized: .app(.allDocuments)),
            systemImage: "tray.full"
          )
        }
      }

      if store.permissions.test(.view, for: .savedView) {
        Section(String(localized: .app(.savedViews))) {
          let savedViews = store.savedViews.map(\.value).sorted { $0.name < $1.name }
          if savedViews.isEmpty {
            Text(.app(.noSavedViews))
              .foregroundStyle(.secondary)
          } else {
            ForEach(savedViews, id: \.id) { sv in
              NavigationLink(value: SidebarSelection.savedView(sv.id)) {
                Label(sv.name, systemImage: "bookmark")
              }
            }
          }
        }
      }
    }
    .navigationTitle(String(localized: .app(.documents)))
    .toolbar { leadingToolbar }
  }

  @ViewBuilder
  private var contentColumn: some View {
    DocumentList(
      store: store,
      onSelect: { selectedDocument = $0 },
      filterModel: filterModel,
      errorController: errorController,
      isFetching: $isFetching,
      selectedDocumentID: selectedDocument?.id
    )
    .safeAreaInset(edge: .top) {
      filterAssemblyView(showsBackdrop: false)
    }
    .navigationTitle(savedViewNavigationTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      // When the sidebar is collapsed (portrait, or user-toggled), the
      // settings/logout/ASN menu becomes unreachable from the sidebar's
      // toolbar — mirror it here so it's still one tap away.
      if columnVisibility != .all {
        leadingToolbar
      }
      trailingToolbar
    }
  }

  @ViewBuilder
  private var detailColumn: some View {
    if let doc = selectedDocument {
      let bridge = Binding<[NavigationState]>(
        get: { [.detail(document: doc)] },
        set: { newValue in
          if newValue.isEmpty { selectedDocument = nil }
        }
      )
      DocumentDetailView(store: store, document: doc, navPath: bridge)
        .id(doc.id)
    } else {
      ContentUnavailableView {
        Label(
          String(localized: .app(.documents)),
          systemImage: "doc.text"
        )
      }
    }
  }

  @ViewBuilder
  private var regularBody: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      sidebarColumn
    } content: {
      NavigationStack { contentColumn }
    } detail: {
      NavigationStack { detailColumn }
    }
    .onChange(of: sidebarSelection) { _, new in
      withAnimation {
        switch new {
        case .none, .allDocuments:
          // Only clear if there's actually something to clear — otherwise
          // the initial reverse-sync (below) ricochets back here and
          // wipes a perfectly valid restored filter.
          if filterModel.filterState.savedView != nil
            || filterModel.filterState.modified
          {
            filterModel.filterState.clear()
          }
        case .savedView(let id):
          // Same idempotency guard: if we're already on this saved view
          // (e.g., we just adopted it from filterState), don't reassign
          // and discard any user modifications restored from defaults.
          if filterModel.filterState.savedView != id, let sv = store.savedViews[id] {
            filterModel.filterState = .init(savedView: sv)
          }
        }
      }
    }
    // initial: true makes the sidebar adopt a saved view that was already
    // present in filterState at mount (restored from UserDefaults).
    .onChange(of: filterModel.filterState.savedView, initial: true) { _, new in
      let target: SidebarSelection = new.map(SidebarSelection.savedView) ?? .allDocuments
      if sidebarSelection != target { sidebarSelection = target }
    }
  }

  // MARK: Main View Body

  var body: some View {
    Group {
      if horizontalSizeClass == .regular {
        regularBody
      } else {
        compactBody
      }
    }

    .fileImporter(
      isPresented: $showFileImporter,
      allowedContentTypes: [.pdf, .image],
      allowsMultipleSelection: true,
      onCompletion: { result in
        Task { @MainActor in
          switch result {
          case .success(let urls):
            showFileImporter = false
            await importModel.importFile(
              result: urls, isSecurityScoped: true, errorController: errorController)
            showCreateModal = true
          case .failure(let failure):
            errorController.push(error: failure)
          }
        }
      }
    )

    .fullScreenCover(isPresented: $showDocumentScanner) {
      DocumentScannerView(
        isPresented: $showDocumentScanner,
        onCompletion: { result in
          Task { @MainActor in
            switch result {
            case .success(let urls):
              showDocumentScanner = false
              await importModel.importFile(
                result: urls, isSecurityScoped: false, errorController: errorController)
              showCreateModal = true
            case .failure(let failure):
              errorController.push(error: failure)
            }
          }
        }
      )
      .ignoresSafeArea()
    }

    .sheet(
      isPresented: $showCreateModal,
      onDismiss: {
        importModel.reset()
      }
    ) {
      DocumentModelWrapper(
        importModel: importModel,
        callback: createCallback,
        title: createDocumentTitle
      )
      .environment(store)
      .environmentObject(errorController)
    }

    .sheet(isPresented: $showDataScanner) {
      DataScannerView(store: store)
    }

    .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotos, matching: .images)

    .onChange(of: selectedPhotos) {
      Logger.shared.info("Photo picker returns \(selectedPhotos.count) photos")
      guard !selectedPhotos.isEmpty else {
        Logger.shared.debug("No photos, nothing to do")
        return
      }

      Task { @MainActor in
        do {
          let url = try await createPDFFrom(photos: selectedPhotos)
          Logger.shared.debug("Have PDF at \(url)")
          await importModel.importFile(
            result: [url], isSecurityScoped: false, errorController: errorController)
          selectedPhotos = []
          showCreateModal = true
        } catch {
          Logger.shared.error("Got error when creating PDF from photos: \(error)")
          errorController.push(error: error)
        }
      }
    }

    .sheet(item: $taskViewNavState, content: tasksSheet)

    .onChange(of: routeManager.pendingRoute, initial: true, handlePendingRoute)

    .task {
      do {
        async let fetch: Void = store.fetchAll()

        (isDataScannerAvailable, isDocumentScannerAvailable) = await (
          DataScannerView.isAvailable, DocumentScannerView.isAvailable
        )

        try await fetch
      } catch {
        errorController.push(error: error)
      }
    }

    .environment(filterModel)
  }

  private func tasksSheet(state: NavigationState) -> some View {
    var navPath = [NavigationState]()
    switch state {
    case .task:
      navPath.append(state)
    case .tasks:
      break
    default:
      fatalError("Invalid task view navigation state pushed")
    }
    return TasksView(navPath: navPath)
      .environment(store)
      .environmentObject(errorController)
  }
}

// - MARK: Previews

#Preview("DocumentView") {
  @Previewable @State var store = DocumentStore(repository: PreviewRepository())
  @Previewable @StateObject var errorController = ErrorController()
  @Previewable @StateObject var connectionManager = ConnectionManager(
    database: try! Database.inMemory())
  @Previewable @State var networkMonitor = NetworkMonitor()
  @Previewable @State var showSettings = false

  DocumentView(showSettings: $showSettings)
    .environment(store)
    .environmentObject(errorController)
    .environmentObject(connectionManager)
    .environment(RouteManager())
    .environment(networkMonitor)
}
