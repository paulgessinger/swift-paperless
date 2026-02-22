//
//  DocumentDetailViewV4.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.02.26.
//

import Common
import DataModel
import Flow
import Networking
import SwiftUI

@MainActor
struct DocumentDetailViewV4: DocumentDetailViewProtocol {
  @State private var viewModel: DocumentDetailModel
  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController

  @State private var showEditSheet = false
  @State private var showMetadataSheet = false
  @State private var showNotesSheet = false
  
  @State private var showPreview = false
  @State private var showShadow = true
  @State private var shadowDelay: Double? = nil

  var navPath: Binding<[NavigationState]>? = nil
  
  @Namespace private var namespace

  init(
    store: DocumentStore,
    connection: Connection?,
    document: Document,
    navPath: Binding<[NavigationState]>?
  ) {
    _viewModel = State(
      initialValue: DocumentDetailModel(
        store: store,
        connection: connection,
        document: document
      )
    )
    self.navPath = navPath
  }

  private var metadataActions: some View {
    HStack(spacing: 12) {
      Button {
        showEditSheet = true
      } label: {
        Label(localized: .localizable(.edit), systemImage: "square.and.pencil")
      }
      .buttonStyle(.borderedProminent)

      Button {
        showMetadataSheet = true
      } label: {
        Label(localized: .documentMetadata(.metadata), systemImage: "info.circle")
      }
      .buttonStyle(.bordered)

      if viewModel.store.permissions.test(.view, for: .note) {
        Button {
          showNotesSheet = true
        } label: {
          Label(localized: .documentMetadata(.notes), systemImage: "note.text")
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private var detailAspects: some View {
    let document = viewModel.document
    return HFlow(itemSpacing: 12) {
      if let asn = document.asn {
        DocumentCellAspect(localized: .localizable(.documentAsn(asn)), systemImage: "qrcode")
      }

      if let id = document.correspondent {
        DocumentCellAspect(store.correspondents[id]?.name, systemImage: "person")
      }

      if let pageCount = document.pageCount {
        DocumentCellAspect(localized: .localizable(.pages(pageCount)), systemImage: "book.pages")
      }

      if let id = document.documentType {
        DocumentCellAspect(store.documentTypes[id]?.name, systemImage: "doc")
      }

      DocumentCellAspect(
        DocumentCell.dateFormatter.string(from: document.created),
        systemImage: "calendar"
      )

      if let id = document.storagePath {
        DocumentCellAspect(store.storagePaths[id]?.name, systemImage: "archivebox")
      }

      if case .user(let id) = document.owner {
        DocumentCellAspect(store.users[id]?.username, systemImage: "person.badge.key")
      }
    }
  }

  var body: some View {
    @Bindable var viewModel = viewModel

    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 16) {
        DocumentPreview(document: viewModel.document)
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
          .shadow(color: Color(.imageShadow).opacity(showShadow ? 1 : 0), radius: 15)
          .backport.matchedTransitionSource(id: "doc", in: namespace)

          .onTapGesture {
            showPreview = true
            showShadow = false
          }

          .animation(.default, value: showShadow)

        Text(viewModel.document.title)
          .font(.title2)
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity, alignment: .leading)

        detailAspects
          .frame(maxWidth: .infinity, alignment: .leading)

        TagsView(tags: viewModel.document.tags.compactMap { store.tags[$0] })
          .frame(maxWidth: .infinity, alignment: .leading)

        metadataActions
      }
      .padding()
    }
    .navigationTitle(String(localized: .localizable(.details)))
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showEditSheet) {
      DocumentEditView(store: store, document: $viewModel.document, navPath: navPath)
        .environmentObject(errorController)
    }
    .sheet(isPresented: $showMetadataSheet) {
      DocumentMetadataView(document: $viewModel.document, metadata: $viewModel.metadata)
        .environmentObject(store)
        .environmentObject(errorController)
    }
    .sheet(isPresented: $showNotesSheet) {
      DocumentNoteView(document: $viewModel.document)
        .environmentObject(store)
        .environmentObject(errorController)
    }
    .sheet(isPresented: $showPreview,
           onDismiss: {
      Task {
        try? await Task.sleep(for: .seconds(shadowDelay ?? 1.0))
        showShadow = true
        shadowDelay = nil
      }
    }) {
      if case let .loaded(url) = viewModel.download {
        NavigationStack {
          SearchablePDFPreview(url: url, onButtonDismiss: {
            shadowDelay = 0.2
          })
            .ignoresSafeArea(.container, edges: .top)
        }
        .backport.navigationTransitionZoom(sourceID: "doc", in: namespace)
      }
    }

    .task {
      await viewModel.loadDocument()
      await viewModel.loadMetadata()
    }
  }
}

// MARK: - Previews

private struct DocumentDetailViewV4PreviewHelper: View {
  @StateObject private var store = DocumentStore(repository: TransientRepository())
  @StateObject private var errorController = ErrorController()
  @StateObject private var connectionManager = ConnectionManager(previewMode: true)

  @State private var document: Document?
  @State private var navPath = [NavigationState]()

  let documentId: UInt

  init(id documentId: UInt) {
    self.documentId = documentId
  }

  var body: some View {
    NavigationStack {
      if let document {
        DocumentDetailViewV4(
          store: store,
          connection: connectionManager.connection,
          document: document,
          navPath: $navPath
        )
      } else {
        Text("No document")
      }
    }
    .environmentObject(store)
    .environmentObject(errorController)
    .environment(RouteManager.shared)
    .task {
      do {
        guard let repository = store.repository as? TransientRepository else {
          return
        }
        repository.addUser(User(id: 1, isSuperUser: true, username: "preview", groups: []))
        try repository.login(userId: 1)

        try await repository.create(
          document: ProtoDocument(
            title: "Preview document",
            asn: 42,
            created: .now
          ),
          url: #URL(
            "https://github.com/paulgessinger/swift-paperless/raw/refs/heads/main/Preview%20PDFs/street.pdf"
          )
        )

        try await store.fetchAll()
        let documents = try await store.repository.documents(filter: .default).fetch(limit: 100_000)
        document = documents.first(where: { $0.id == documentId }) ?? documents.first
      } catch {
        print(error)
      }
    }
  }
}

#Preview("DocumentDetailViewV4") {
  DocumentDetailViewV4PreviewHelper(id: 2)
}
