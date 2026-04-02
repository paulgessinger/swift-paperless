//
//  DocumentDetailViewV4.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.02.26.
//

import Common
import DataModel
import Networking
import SwiftUI

private enum ActiveSheet: Identifiable, Hashable {
  case title
  case tags
  case asn
  case correspondent
  case documentType
  case date
  case storagePath
  case owner
  case metadata
  case notes
  case shareLink

  var id: Self { self }
}

@MainActor
struct DocumentDetailViewV4: DocumentDetailViewProtocol {
  @State private var viewModel: DocumentDetailModel
  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController

  @State private var activeSheet: ActiveSheet? = nil
  @State private var showPreview = false
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

  private var detailAspects: some View {
    let document = viewModel.document
    return HFlow(itemSpacing: 12) {
      if let asn = document.asn {
        EditableAspect(
          localized: .localizable(.documentAsn(asn)),
          systemImage: "qrcode",
          action: {
            activeSheet = .asn
          },
          transitionID: .asn,
          namespace: namespace
        )
      }

      EditableAspect(
        document.correspondent.flatMap { store.correspondents[$0]?.name },
        systemImage: "person.fill",
        action: {
          activeSheet = .correspondent
        },
        transitionID: .correspondent,
        namespace: namespace,
        showPrivateFallback: false,
        accessibilityLabel: document.correspondent == nil
          ? String(localized: .localizable(.correspondentNotAssignedPicker)) : nil
      )

      EditableAspect(
        document.documentType.flatMap { store.documentTypes[$0]?.name },
        systemImage: "doc.fill",
        action: {
          activeSheet = .documentType
        },
        transitionID: .documentType,
        namespace: namespace,
        showPrivateFallback: false,
        accessibilityLabel: document.documentType == nil
          ? String(localized: .localizable(.documentTypeNotAssignedPicker)) : nil
      )

      EditableAspect(
        DocumentCell.dateFormatter.string(from: document.created),
        systemImage: "calendar",
        action: {
          activeSheet = .date
        },
        transitionID: .date,
        namespace: namespace
      )

      EditableAspect(
        document.storagePath.flatMap { store.storagePaths[$0]?.name },
        systemImage: "archivebox.fill",
        action: {
          activeSheet = .storagePath
        },
        transitionID: .storagePath,
        namespace: namespace,
        showPrivateFallback: false,
        accessibilityLabel: document.storagePath == nil
          ? String(localized: .localizable(.storagePathNotAssignedPicker)) : nil
      )

      if case .user(let id) = document.owner {
        EditableAspect(
          store.users[id]?.username,
          systemImage: "person.badge.key.fill",
          action: {
            activeSheet = .owner
          },
          transitionID: .owner,
          namespace: namespace
        )
      }
    }
  }

  private struct BottomBarButton: View {
    let label: LocalizedStringResource
    let image: String
    let action: () -> Void
    let transitionID: TransitionID
    let namespace: Namespace.ID

    var body: some View {
      Button(action: action) {
        Label(localized: label, systemImage: image)
          .font(.title2)
          .labelStyle(.iconOnly)
          .padding(10)
          .backport.matchedTransitionSource(id: transitionID, in: namespace)
          .backport.glassEffect(.regular.interactive())
      }
      .foregroundStyle(.primary)
    }
  }

  private var metadataBar: some View {
    GlassEffectContainerCompat {
      HStack {
        BottomBarButton(
          label: .documentMetadata(.metadata), image: "info.circle",
          action: {
            activeSheet = .metadata
          },
          transitionID: .metadata,
          namespace: namespace
        )

        BottomBarButton(
          label: .documentMetadata(.notes), image: "note.text",
          action: {
            activeSheet = .notes
          },
          transitionID: .notes,
          namespace: namespace
        )
      }
      .apply {
        if #unavailable(iOS 26.0) {
          $0.background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
              .fill(.thinMaterial)
          }
        } else {
          $0
        }
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding()
    }
  }

  @ViewBuilder
  private var shareMenuContent: some View {
    Button {
      activeSheet = .shareLink
    } label: {
      Label(localized: .localizable(.shareLink), systemImage: "link")
    }

    if let url = viewModel.documentUrl {
      ShareLink(item: url) {
        Label(localized: .localizable(.documentLink), systemImage: "safari")
      }
    }

    Menu {
      let deepLinks = viewModel.deepLinks

      if let url = deepLinks.withoutServer?.url {
        ShareLink(item: url) {
          Text(.localizable(.documentDeepLinkWithoutBackend))
        }
      }

      if let url = deepLinks.withServer?.url {
        ShareLink(item: url) {
          Text(.localizable(.documentDeepLinkWithBackend))
        }
      }
    } label: {
      Label(localized: .localizable(.documentDeepLink), systemImage: "app")
    }

    if case .loaded(url: let url, document: _) = viewModel.download {
      ShareLink(item: url) {
        Label(localized: .localizable(.shareSheet), systemImage: "document")
      }
    }
  }

  private var previewEnabled: Bool {
    switch viewModel.download {
    case .loaded:
      return true
    default:
      return false
    }
  }

  var body: some View {
    @Bindable var viewModel = viewModel

    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 16) {
        Button {
          guard previewEnabled else { return }
          showPreview = true
        } label: {
          DocumentPreview(document: viewModel.document)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomTrailing) {
              if let pageCount = viewModel.document.pageCount {
                HStack(spacing: 4) {
                  Image(systemName: "book.pages.fill")
                  Text("\(pageCount)")
                }
                .font(.footnote)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .backport.glassEffect(
                  .regular, in: Capsule(), orFill: .ultraThinMaterial
                )
                .padding(10)
              }
            }
            .backport.matchedTransitionSource(id: TransitionID.doc, in: namespace)
            .accessibilityLabel(.localizable(.documentOpen))
        }
        .disabled(!previewEnabled)

        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .shadow(color: Color(.imageShadow), radius: 15)

        DocumentTitleView(
          title: viewModel.document.title,
          transitionID: .title,
          namespace: namespace,
          action: { activeSheet = .title }
        )

        detailAspects
          .animation(.spring(duration: 0.25), value: viewModel.document)

        DocumentTagsSection(
          tags: viewModel.document.tags.map { store.tags[$0] },
          action: {
            activeSheet = .tags
          },
          transitionID: .tags,
          namespace: namespace
        )
      }
      .padding()
    }
    .refreshable {
      let model = viewModel
      async let document = model.loadDocument()
      async let metadata = model.loadMetadata()
      _ = await (document, metadata)
    }
    .navigationTitle(String(localized: .localizable(.details)))
    .navigationBarTitleDisplayMode(.inline)

    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          shareMenuContent
        } label: {
          Label(localized: .localizable(.share), systemImage: "square.and.arrow.up")
            .labelStyle(.iconOnly)
        }
      }
    }

    .apply {
      if #available(iOS 26.0, *) {
        $0.safeAreaInset(edge: .bottom) {
          metadataBar
        }
      } else {
        $0.safeAreaInset(edge: .bottom) {
          metadataBar
        }
      }
    }

    .sheet(item: $activeSheet) { sheet in
      switch sheet {
      case .title:
        TitleEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.title, in: namespace)

      case .tags:
        TagsEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.tags, in: namespace)
          .presentationDetents([.medium, .large])

      case .asn:
        NavigationStack {
          Text("ASN")
            .navigationTitle("ASN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                CancelIconButton()
              }
            }
        }
        .sheetZoomTransition(sourceID: TransitionID.asn, in: namespace)
        .presentationDetents([.medium])

      case .correspondent:
        CorrespondentEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.correspondent, in: namespace)
          .presentationDetents([.medium, .large])

      case .documentType:
        DocumentTypeEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.documentType, in: namespace)
          .presentationDetents([.medium, .large])

      case .date:
        NavigationStack {
          Text("Date")
            .navigationTitle("Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                CancelIconButton()
              }
            }
        }
        .sheetZoomTransition(sourceID: TransitionID.date, in: namespace)
        .presentationDetents([.medium])

      case .storagePath:
        NavigationStack {
          Text("Storage Path")
            .navigationTitle("Storage Path")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                CancelIconButton()
              }
            }
        }
        .sheetZoomTransition(sourceID: TransitionID.storagePath, in: namespace)
        .presentationDetents([.medium])

      case .owner:
        NavigationStack {
          Text("Owner")
            .navigationTitle("Owner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                CancelIconButton()
              }
            }
        }
        .sheetZoomTransition(sourceID: TransitionID.owner, in: namespace)
        .presentationDetents([.medium])

      case .metadata:
        DocumentMetadataView(document: $viewModel.document, metadata: $viewModel.metadata)
          .environmentObject(store)
          .environmentObject(errorController)
          .sheetZoomTransition(sourceID: TransitionID.metadata, in: namespace)

      case .notes:
        DocumentNoteView(document: $viewModel.document)
          .environmentObject(store)
          .environmentObject(errorController)
          .sheetZoomTransition(sourceID: TransitionID.notes, in: namespace)

      case .shareLink:
        ShareLinkView(document: viewModel.document)
      }
    }

    .sheet(
      isPresented: $showPreview,
      onDismiss: {
        Task {
          try? await Task.sleep(for: .seconds(shadowDelay ?? 1.0))
          shadowDelay = nil
        }
      }
    ) {
      if case .loaded(url: _, document: let document) = viewModel.download {
        NavigationStack {
          SearchablePDFPreview(
            document: document,
            onButtonDismiss: {
              shadowDelay = 0.2
            }
          )
          .ignoresSafeArea(.container)
          .navigationBarTitleDisplayMode(.inline)
          .navigationTitle(viewModel.document.title)
        }
        // Preview is full-screen; other sheets keep `sheetZoomTransition` (iOS 26+) for detents.
        .backport.navigationTransitionZoom(sourceID: TransitionID.doc, in: namespace)
      }
    }

    .task {
      await viewModel.loadDocument()
      await viewModel.loadMetadata()
    }
  }
}

// MARK: - Helpers

extension View {
  /// Applies `.zoom` navigation transition only on iOS 26+.
  /// On iOS 18, the zoom transition forces full-screen presentation which breaks sheet detent interaction.
  fileprivate func sheetZoomTransition(sourceID: some Hashable, in namespace: Namespace.ID)
    -> some View
  {
    apply {
      if #available(iOS 26.0, *) {
        $0.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
      } else {
        $0
      }
    }
  }
}

// MARK: - Previews

extension Tag {
  fileprivate init(name: String, color: Color) {
    self.init(
      id: 0, isInboxTag: false, name: name, slug: "", color: color.hex, match: "",
      matchingAlgorithm: .auto, isInsensitive: true)
  }
}

#Preview("EditableAspect", traits: .sizeThatFitsLayout) {
  VStack(alignment: .leading, spacing: 12) {
    EditableAspect(localized: .localizable(.documentAsn(42)), systemImage: "qrcode")
    EditableAspect("Preview Correspondent", systemImage: "person.fill")
    EditableAspect("Preview Type", systemImage: "doc.fill")
    EditableAspect(nil, systemImage: "person.badge.key.fill")

    DocumentTagsSection(
      tags: [
        Tag(name: "Inbox", color: Color.purple),
        Tag(name: "Bank", color: Color.blue),
        Tag(name: "Travel Document", color: Color.green),
        Tag(name: "Short", color: Color.green),
        Tag(name: "Important", color: Color.red),
        Tag(name: "Book", color: Color.yellow),
        Tag(
          name: "I am a very long tag name that will not fit in most places in the UI",
          color: Color.red),
        nil,
      ],
      action: nil,
      transitionID: nil,
      namespace: nil
    )
  }
  .padding()
}

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
    .environment(ImagePipelineProvider())
    .task {
      do {
        guard let repository = store.repository as? TransientRepository else {
          return
        }
        repository.addUser(User(id: 1, isSuperUser: true, username: "preview", groups: []))
        try repository.login(userId: 1)

        let correspondent = try await repository.create(
          correspondent: ProtoCorrespondent(name: "Some bank")
        )
        _ = try await repository.create(
          correspondent: ProtoCorrespondent(name: "Health Insurance Co.")
        )
        let documentType = try await repository.create(
          documentType: ProtoDocumentType(name: "Preview Type")
        )
        let storagePath = try await repository.create(
          storagePath: ProtoStoragePath(name: "Preview Storage")
        )
        let inboxTag = try await repository.create(
          tag: ProtoTag(name: "Inbox", color: Color.blue.hex))
        let financeTag = try await repository.create(
          tag: ProtoTag(name: "Finance", color: Color.green.hex)
        )
        let urgentTag = try await repository.create(
          tag: ProtoTag(name: "Urgent", color: Color.red.hex))
        let taxesTag = try await repository.create(
          tag: ProtoTag(name: "Taxes", color: Color.orange.hex))
        let personalTag = try await repository.create(
          tag: ProtoTag(name: "Personal", color: Color.purple.hex)
        )
        let archiveTag = try await repository.create(
          tag: ProtoTag(name: "Archive", color: Color.gray.hex))

        try await repository.create(
          document: ProtoDocument(
            title: "Preview document",
            // title:
            //   "Preview document which has a title that is very long and also needs to be handled without completely breaking the layout",
            asn: 42,
            documentType: documentType.id,
            correspondent: correspondent.id,
            tags: [
              inboxTag.id, financeTag.id, urgentTag.id, taxesTag.id, personalTag.id, archiveTag.id,
            ],
            created: Calendar.current.date(byAdding: .day, value: -10, to: .now) ?? .now,
            storagePath: storagePath.id
          ),
          url: #URL(
            "https://github.com/paulgessinger/swift-paperless/raw/refs/heads/main/Preview%20PDFs/street.pdf"
          )
        )

        try await store.fetchAll()
        let documents = try await store.repository.documents(filter: .default).fetch(limit: 100_000)
        let firstDocument = documents.first
        if var firstDocument {
          firstDocument.owner = .user(1)
          firstDocument.pageCount = 12
          firstDocument.tags.append(666)
          document = try await repository.update(document: firstDocument)
        }
      } catch {
        print(error)
      }
    }
  }
}

#Preview("DocumentDetailViewV4") {
  DocumentDetailViewV4PreviewHelper(id: 2)
}
