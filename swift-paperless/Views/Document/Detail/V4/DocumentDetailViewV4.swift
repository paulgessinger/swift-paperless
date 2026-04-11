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
  case customFields
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
  @State private var previewPage = 0
  @State private var shadowDelay: Double? = nil
  @State private var showDeleteConfirmation = false
  @State private var deleted = false

  @ObservedObject private var appSettings = AppSettings.shared

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

  private func deleteDocument() {
    Task { @MainActor in
      do {
        try await store.deleteDocument(viewModel.document)
        deleted = true
        Haptics.shared.impact(style: .rigid)
        try await Task.sleep(for: .seconds(0.2))
        if let navPath {
          navPath.wrappedValue = []
        }
      } catch {
        errorController.push(error: error)
      }
    }
  }

  private func aspectLabel<T: Named>(id: UInt?, in collection: [UInt: T]) -> AspectLabel {
    guard let id else { return .notAssigned }
    guard let item = collection[id] else { return .private }
    return .text(item.name)
  }

  private var detailAspects: some View {
    let document = viewModel.document
    let canChange = store.userCanChange(document: document)
    let asnLabel: AspectLabel =
      document.asn.map { .text(String(localized: .localizable(.documentAsn($0)))) } ?? .notAssigned
    return HFlow(itemSpacing: 12) {
      EditableAspect(
        label: asnLabel,
        systemImage: "qrcode",
        action: { activeSheet = .asn },
        transitionID: .asn,
        namespace: namespace,
        enabled: canChange
      )

      EditableAspect(
        label: aspectLabel(id: document.correspondent, in: store.correspondents),
        systemImage: "person.fill",
        action: { activeSheet = .correspondent },
        transitionID: .correspondent,
        namespace: namespace,
        enabled: canChange
      )

      EditableAspect(
        label: aspectLabel(id: document.documentType, in: store.documentTypes),
        systemImage: "doc.fill",
        action: { activeSheet = .documentType },
        transitionID: .documentType,
        namespace: namespace,
        enabled: canChange
      )

      EditableAspect(
        label: .text(DocumentCell.dateFormatter.string(from: document.created)),
        systemImage: "calendar",
        action: { activeSheet = .date },
        transitionID: .date,
        namespace: namespace,
        enabled: canChange
      )

      EditableAspect(
        label: aspectLabel(id: document.storagePath, in: store.storagePaths),
        systemImage: "archivebox.fill",
        action: { activeSheet = .storagePath },
        transitionID: .storagePath,
        namespace: namespace,
        enabled: canChange
      )

      EditableAspect(
        label: aspectLabel(
          id: { if case .user(let id) = document.owner { return id } else { return nil } }(),
          in: store.users
        ),
        systemImage: "person.badge.key.fill",
        action: { activeSheet = .owner },
        transitionID: .owner,
        namespace: namespace,
        enabled: canChange
      )

      EditableAspect(
        label: .text(String(localized: .customFields(.title))),
        systemImage: "list.bullet.rectangle.fill",
        action: { activeSheet = .customFields },
        transitionID: .customFields,
        namespace: namespace,
        enabled: canChange
      )
    }
  }

  @ViewBuilder
  private var readOnlyExplanation: some View {
    let document = viewModel.document
    if !store.userCanChange(document: document) {
      let reason: LocalizedStringResource = if !store.permissions.test(.change, for: .document) {
        .localizable(.documentReadOnlyNoGlobalPermission)
      } else if case .user(let ownerId) = document.owner, let owner = store.users[ownerId] {
        .localizable(.documentReadOnlyOwnedBy(owner.username))
      } else {
        .localizable(.documentReadOnlyNotOwner)
      }

      Label {
        Text(reason)
      } icon: {
        Image(systemName: "lock.fill")
          .foregroundStyle(.secondary)
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }

  private struct BottomBarButton<S: ShapeStyle>: View {
    let label: LocalizedStringResource
    let image: String
    let action: () -> Void
    let transitionID: TransitionID?
    let namespace: Namespace.ID?
    let badge: String?
    let style: S

    @ScaledMetric(relativeTo: .title2) private var iconSize = 24

    init(
      label: LocalizedStringResource,
      image: String,
      action: @escaping () -> Void,
      transitionID: TransitionID? = nil,
      namespace: Namespace.ID? = nil,
      badge: String? = nil,
      style: S = .primary
    ) {
      self.label = label
      self.image = image
      self.action = action
      self.transitionID = transitionID
      self.namespace = namespace
      self.badge = badge
      self.style = style
    }

    var body: some View {
      Button(action: action) {
        HStack {
          Label(localized: label, systemImage: image)
            .font(.title2)
            .labelStyle(.iconOnly)
            .frame(width: iconSize, height: iconSize)

          if let badge {
            Text(badge)
          }
        }
        .padding(10)
        .apply {
          if let transitionID, let namespace {
            $0.backport.matchedTransitionSource(id: transitionID, in: namespace)
          } else {
            $0
          }
        }
        .backport.glassEffect(.regular.interactive())
      }
      .foregroundStyle(style)
    }
  }

  @ViewBuilder
  private var metadataBar: some View {
    GlassEffectContainerCompat {
      HStack {
        BottomBarButton(
          label: .documentMetadata(.metadata), image: "info.circle",
          action: {
            activeSheet = .metadata
          },
          transitionID: .metadata,
          namespace: namespace,
          badge: nil
        )

        BottomBarButton(
          label: .documentMetadata(.notes), image: "note.text",
          action: {
            activeSheet = .notes
          },
          transitionID: .notes,
          namespace: namespace,
          badge: viewModel.document.notes.count > 0 ? "\(viewModel.document.notes.count)" : nil
        )

        let canDelete = store.userCanDelete(document: viewModel.document)

        BottomBarButton(
          label: deleted ? .localizable(.documentDeleted) : .localizable(.delete),
          image: deleted ? "checkmark.circle.fill" : canDelete ? "trash" : "trash.slash",
          action: {
            if appSettings.documentDeleteConfirmation {
              showDeleteConfirmation = true
            } else {
              deleteDocument()
            }
          },
          style: canDelete ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary)
        )
        .contentTransition(.symbolEffect)
        .disabled(!canDelete)
        .opacity(1)
        .confirmationDialog(
          String(localized: .localizable(.confirmationPromptTitle)),
          isPresented: $showDeleteConfirmation,
          titleVisibility: .visible
        ) {
          Button(String(localized: .localizable(.delete)), role: .destructive) {
            deleteDocument()
          }
          Button(String(localized: .localizable(.cancel)), role: .cancel) {}
        }
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
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
    .padding()
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

    Divider()

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
          DocumentPreview(
            document: viewModel.document,
            downloadState: viewModel.download,
            currentPage: $previewPage
          )
            .frame(maxWidth: .infinity)
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
          action: { activeSheet = .title },
          enabled: store.userCanChange(document: viewModel.document)
        )

        readOnlyExplanation

        detailAspects
          .animation(.spring(duration: 0.25), value: viewModel.document)

        DocumentTagsSection(
          tags: viewModel.document.tags.map { store.tags[$0] },
          action: {
            activeSheet = .tags
          },
          transitionID: .tags,
          namespace: namespace,
          enabled: store.userCanChange(document: viewModel.document)
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
        AsnEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.asn, in: namespace)
          .presentationDetents([.fraction(0.25), .medium])

      case .correspondent:
        CorrespondentEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.correspondent, in: namespace)
          .presentationDetents([.medium, .large])

      case .documentType:
        DocumentTypeEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.documentType, in: namespace)
          .presentationDetents([.medium, .large])

      case .date:
        DateEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.date, in: namespace)
          .presentationDetents([.fraction(0.25), .medium])

      case .storagePath:
        StoragePathEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.storagePath, in: namespace)
          .presentationDetents([.medium, .large])

      case .owner:
        OwnerEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.owner, in: namespace)
          .presentationDetents([.medium, .large])

      case .customFields:
        CustomFieldsEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.customFields, in: namespace)

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
            },
            currentPage: $previewPage
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
      try? await viewModel.loadSuggestions()
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
    EditableAspect(
      label: .text(String(localized: .localizable(.documentAsn(42)))), systemImage: "qrcode")
    EditableAspect(label: .text("Preview Correspondent"), systemImage: "person.fill")
    EditableAspect(label: .text("Preview Type"), systemImage: "doc.fill")
    EditableAspect(label: .notAssigned, systemImage: "person.badge.key.fill")
    EditableAspect(label: .private, systemImage: "person.badge.key.fill")

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
        let healthInsurance = try await repository.create(
          correspondent: ProtoCorrespondent(name: "Health Insurance Co.")
        )
        let documentType = try await repository.create(
          documentType: ProtoDocumentType(name: "Preview Type")
        )
        let invoiceType = try await repository.create(
          documentType: ProtoDocumentType(name: "Invoice")
        )
        let storagePath = try await repository.create(
          storagePath: ProtoStoragePath(name: "Preview Storage")
        )
        let archivePath = try await repository.create(
          storagePath: ProtoStoragePath(name: "Archive/2026")
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

          repository.setSuggestions(
            Suggestions(
              correspondents: [healthInsurance.id],
              tags: [financeTag.id, archiveTag.id],
              documentTypes: [invoiceType.id],
              storagePaths: [archivePath.id],
              dates: [
                Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now,
                Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now,
              ]
            ),
            for: firstDocument.id
          )
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
