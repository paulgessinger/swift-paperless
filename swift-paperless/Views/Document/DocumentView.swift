//
//  DocumentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import AsyncAlgorithms
import Combine
import DataModel
import Networking
import PhotosUI
import QuickLook
import SwiftUI
import os

enum NavigationState: Equatable, Hashable, Identifiable {
  case root
  case detail(document: Document)
  case settings
  case tasks
  case task(_: PaperlessTask)

  var id: UInt {
    switch self {
    case .root: 1
    case .detail: 2
    case .settings: 3
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

@MainActor
struct DocumentView: View {
  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var connectionManager: ConnectionManager
  @EnvironmentObject private var errorController: ErrorController

  @StateObject private var filterModel = FilterModel()

  // MARK: State

  @State private var navPath = NavigationPath()

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
  @State private var showTypeAsn = false
  @State private var taskViewNavState: NavigationState? = nil
  @State private var showSettings = false

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
    case .settings:
      SettingsView()
    default:
      fatalError()
    }
  }

  private var savedViewNavigationTitle: String {
    guard let id = filterModel.filterState.savedView else {
      // No saved view active
      return String(localized: .localizable(.documents))
    }
    guard let savedView = store.savedViews[id] else {
      // Not necessarily an error, might be still loading
      return String(localized: .localizable(.documents))
    }
    if filterModel.filterState.modified {
      return String(localized: .localizable(.savedViewModified(savedView.name)))
    } else {
      return savedView.name
    }
  }

  private var createDocumentTitle: String {
    if importModel.totalUrls > 1 {
      "\(String(localized: .localizable(.documentAdd))) (\(importModel.remaining) / \(importModel.totalUrls))"
    } else {
      String(localized: .localizable(.documentAdd))
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .navigationBarTrailing) {
      TaskActivityToolbar(navState: $taskViewNavState)

      Menu {
        if isDocumentScannerAvailable {
          Button {
            showDocumentScanner = true
          } label: {
            Label(String(localized: .localizable(.scanDocument)), systemImage: "doc.viewfinder")
          }
        }

        Button {
          showFileImporter = true
        } label: {
          Label(
            String(localized: .localizable(.importDocument)), systemImage: "folder.badge.plus")
        }

        Button {
          showPhotosPicker = true
        } label: {
          Label(String(localized: .localizable(.importPhotos)), systemImage: "photo")
        }
      } label: {
        Label(String(localized: .localizable(.add)), systemImage: "plus")
      }
      .tint(.accent)
    }

    ToolbarItemGroup(placement: .navigationBarLeading) {
      Menu {

        Button {
          showSettings = true
        } label: {
          Label(String(localized: .settings(.title)), systemImage: "gear")
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
              for i in 0..<10 {
                errorController.push(
                  message: "Error no \(i)", details: i % 2 == 0 ? "Some details" : nil)
              }
            }
          }
        #endif

        Divider()

        Button(role: .destructive) {
          logoutRequested = true
        } label: {
          Label(
            String(localized: .localizable(.logout)),
            systemImage: "rectangle.portrait.and.arrow.right")
        }

      } label: {
        Label(String(localized: .localizable(.detailsMenuLabel)), systemImage: "ellipsis.circle")
          .labelStyle(.iconOnly)
      }
      .tint(.accent)

      if isDataScannerAvailable {
        Button {
          Task {
            try? await Task.sleep(for: .seconds(0.1))
            showDataScanner = true
          }
        } label: {
          Label(String(localized: .localizable(.toolbarAsnButton)), systemImage: "number.circle")
        }
        .tint(.accent)
      } else {
        Button {
          withAnimation(.spring(response: 0.5)) {
            showTypeAsn.toggle()
          }
        } label: {
          Label(String(localized: .localizable(.toolbarAsnButton)), systemImage: "number.circle")
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
        Text(.localizable(.allDocuments))
      }
    }

    Section(String(localized: .localizable(.savedViews))) {
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
          Text(.localizable(.noSavedViews))
        }
      } else {
        Text(.permissions(.noViewPermissionsSavedViews))
      }
    }
  }

  // MARK: Main View Body

  var body: some View {
    NavigationStack(path: $navPath) {
      DocumentList(
        store: store, navPath: $navPath,
        filterModel: filterModel,
        errorController: errorController
      )

      .safeAreaInset(edge: .top) {
        if #available(iOS 26.0, *) {
          FilterAssembly(filterModel: filterModel)
        } else {
          FilterAssemblyiOS18(filterModel: filterModel)
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
        toolbar
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
        .environmentObject(store)
        .environmentObject(errorController)
      }

      .sheet(isPresented: $showDataScanner, onDismiss: {}) {
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

      .fullScreenConfirmationDialog(
        String(localized: .localizable(.confirmationPromptTitle)), isPresented: $logoutRequested
      ) {
        Button(String(localized: .localizable(.logout)), role: .destructive) {
          connectionManager.logout(animated: true)
        }
        Button(String(localized: .localizable(.cancel)), role: .cancel) {}
      }

      .sheet(isPresented: $showSettings) {
        SettingsView()
      }

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
      .environmentObject(store)
      .environmentObject(errorController)
      .errorOverlay(errorController: errorController, offset: 15)
  }
}

// - MARK: Previews

#Preview("DocumentView") {
  @Previewable @StateObject var store = DocumentStore(repository: PreviewRepository())
  @Previewable @StateObject var errorController = ErrorController()
  @Previewable @StateObject var connectionManager = ConnectionManager()

  DocumentView()
    .environmentObject(store)
    .environmentObject(errorController)
    .environmentObject(connectionManager)
}
