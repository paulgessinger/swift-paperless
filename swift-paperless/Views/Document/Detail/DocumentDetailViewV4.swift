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
import UIKit

@MainActor
struct DocumentDetailViewV4: DocumentDetailViewProtocol {
  @State private var viewModel: DocumentDetailModel
  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController

  @State private var showEditSheet = false
  @State private var showMetadataSheet = false
  @State private var showNotesSheet = false
  @State private var showPreview = false

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

  private func quickLookShareMenu(_ viewModel: DocumentDetailModel) -> UIMenu? {
    var elements: [UIMenuElement] = []

    if let url = viewModel.documentUrl {
      elements.append(
        UIAction(
          title: String(localized: .localizable(.documentLink)),
          image: UIImage(systemName: "safari")
        ) { _ in
          UIPasteboard.general.url = url
        }
      )
    }

    let deepLinks = viewModel.deepLinks

    if let url = deepLinks.withoutServer?.url {
      elements.append(
        UIAction(
          title: String(localized: .localizable(.documentDeepLinkWithoutBackend)),
          image: UIImage(systemName: "app")
        ) { _ in
          UIPasteboard.general.url = url
        }
      )
    }

    if let url = deepLinks.withServer?.url {
      elements.append(
        UIAction(
          title: String(localized: .localizable(.documentDeepLinkWithBackend)),
          image: UIImage(systemName: "app.badge.checkmark")
        ) { _ in
          UIPasteboard.general.url = url
        }
      )
    }

    guard !elements.isEmpty else { return nil }
    return UIMenu(children: elements)
  }

  var body: some View {
    @Bindable var viewModel = viewModel

    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 16) {
        DocumentPreview(document: viewModel.document)
          .frame(maxWidth: .infinity)
          .onTapGesture {
            showPreview = true
          }
          .backport.matchedTransitionSource(id: "doc", in: namespace)

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
    .sheet(isPresented: $showPreview) {
      if case let .loaded(url) = viewModel.download {
        QuickLookPreview(
          url: url,
          title: "",
          onClose: {
            showPreview = false
          },
          customShareMenu: quickLookShareMenu(viewModel)
        )
        .ignoresSafeArea()
        .backport.navigationTransitionZoom(sourceID: "doc", in: namespace)
//        .presentationDetents([.medium, .large])
      }
    }

    .task {
      await viewModel.loadDocument()
      await viewModel.loadMetadata()
    }
  }
}
