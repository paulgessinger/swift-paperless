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

/// Per-field editors. On regular size class these render as popovers anchored
/// to the source aspect; on compact they adapt back to sheets. Splitting these
/// out from the auxiliary, always-sheet presentations lets each anchor
/// independently.
private enum FieldEdit: Identifiable, Hashable {
  case title
  case tags
  case asn
  case correspondent
  case documentType
  case date
  case storagePath
  case owner
  case customFields

  var id: Self { self }

  init?(field: Route.Action.EditTarget.Field) {
    switch field {
    case .title: self = .title
    case .tags: self = .tags
    case .asn: self = .asn
    case .correspondent: self = .correspondent
    case .documentType: self = .documentType
    case .date: self = .date
    case .storagePath: self = .storagePath
    case .owner: self = .owner
    case .customFields: self = .customFields
    case .notes: return nil
    }
  }
}

/// Auxiliary presentations that always render as sheets regardless of size
/// class — they're large list/detail views that don't make sense as popovers.
private enum AuxiliarySheet: Identifiable, Hashable {
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
  @Environment(RouteManager.self) private var routeManager
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  @State private var activeFieldEdit: FieldEdit? = nil
  @State private var activeSheet: AuxiliarySheet? = nil
  @State private var showPreview = false
  @State private var previewPage = 0
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

  private func handlePendingRoute() {
    guard let action = routeManager.pendingRoute?.action,
      case .document(let docId, let edit) = action,
      docId == viewModel.document.id
    else { return }
    routeManager.pendingRoute = nil
    guard case .field(let field) = edit else { return }
    if let fieldEdit = FieldEdit(field: field) {
      activeFieldEdit = fieldEdit
    } else if field == .notes {
      activeSheet = .notes
    }
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
    @Bindable var viewModel = viewModel
    let document = viewModel.document
    let canChange = store.userCanChange(document: document)
    let asnLabel: AspectLabel =
      document.asn.map { .text(String(localized: .localizable(.documentAsn($0)))) } ?? .notAssigned
    let columns = [
      GridItem(.flexible(), spacing: 12),
      GridItem(.flexible(), spacing: 12),
    ]
    return LazyVGrid(columns: columns, spacing: 12) {
      EditableAspect(
        title: .localizable(.asn),
        label: asnLabel,
        systemImage: "qrcode",
        action: { activeFieldEdit = .asn },
        transitionID: .asn,
        namespace: namespace,
        enabled: canChange
      )
      .editPopover(
        forFieldEdit: .asn,
        active: $activeFieldEdit,
        detents: [.fraction(0.25), .medium],
        popoverSize: CGSize(width: 380, height: 240)
      ) {
        AsnEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.asn, in: namespace)
      }

      EditableAspect(
        title: .localizable(.correspondent),
        label: aspectLabel(id: document.correspondent, in: store.correspondents),
        systemImage: "person.fill",
        action: { activeFieldEdit = .correspondent },
        transitionID: .correspondent,
        namespace: namespace,
        enabled: canChange
      )
      .editPopover(forFieldEdit: .correspondent, active: $activeFieldEdit) {
        CorrespondentEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.correspondent, in: namespace)
      }

      EditableAspect(
        title: .localizable(.documentType),
        label: aspectLabel(id: document.documentType, in: store.documentTypes),
        systemImage: "doc.fill",
        action: { activeFieldEdit = .documentType },
        transitionID: .documentType,
        namespace: namespace,
        enabled: canChange
      )
      .editPopover(forFieldEdit: .documentType, active: $activeFieldEdit) {
        DocumentTypeEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.documentType, in: namespace)
      }

      EditableAspect(
        title: .localizable(.documentEditCreatedDateLabel),
        label: .text(DocumentCell.dateFormatter.string(from: document.created)),
        systemImage: "calendar",
        action: { activeFieldEdit = .date },
        transitionID: .date,
        namespace: namespace,
        enabled: canChange
      )
      .editPopover(
        forFieldEdit: .date,
        active: $activeFieldEdit,
        detents: [.fraction(0.25), .medium],
        popoverSize: CGSize(width: 380, height: 440)
      ) {
        DateEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.date, in: namespace)
      }

      EditableAspect(
        title: .localizable(.storagePath),
        label: aspectLabel(id: document.storagePath, in: store.storagePaths),
        systemImage: "archivebox.fill",
        action: { activeFieldEdit = .storagePath },
        transitionID: .storagePath,
        namespace: namespace,
        enabled: canChange
      )
      .editPopover(forFieldEdit: .storagePath, active: $activeFieldEdit) {
        StoragePathEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.storagePath, in: namespace)
      }

      EditableAspect(
        title: .localizable(.sortOrderOwner),
        label: aspectLabel(
          id: { if case .user(let id) = document.owner { return id } else { return nil } }(),
          in: store.users
        ),
        systemImage: "person.badge.key.fill",
        action: { activeFieldEdit = .owner },
        transitionID: .owner,
        namespace: namespace,
        enabled: canChange
      )
      .editPopover(
        forFieldEdit: .owner,
        active: $activeFieldEdit,
        detents: [.medium, .large]
      ) {
        OwnerEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.owner, in: namespace)
      }

      EditableAspect(
        label: .text(String(localized: .customFields(.title))),
        systemImage: "list.bullet.rectangle.fill",
        action: { activeFieldEdit = .customFields },
        transitionID: .customFields,
        namespace: namespace,
        enabled: canChange
      )
      .editPopover(forFieldEdit: .customFields, active: $activeFieldEdit) {
        CustomFieldsEditSheet(viewModel: viewModel)
          .sheetZoomTransition(sourceID: TransitionID.customFields, in: namespace)
      }
    }
  }

  @ViewBuilder
  private var readOnlyExplanation: some View {
    let document = viewModel.document
    if !store.userCanChange(document: document) {
      let reason: LocalizedStringResource =
        if !store.permissions.test(.change, for: .document) {
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

    let archiveURL: URL? =
      if case .loaded(url: let url, document: _) = viewModel.download { url } else { nil }
    let originalURL: URL? =
      if case .loaded(url: let url) = viewModel.originalDownload { url } else { nil }

    Menu {
      ShareLink(item: archiveURL ?? URL(filePath: "/")) {
        Label(localized: .localizable(.shareArchive), systemImage: "doc.zipper")
      }
      .disabled(archiveURL == nil)

      ShareLink(item: originalURL ?? URL(filePath: "/")) {
        Label(localized: .localizable(.shareOriginal), systemImage: "doc")
      }
      .disabled(originalURL == nil)
    } label: {
      Label(localized: .localizable(.shareDocument), systemImage: "square.and.arrow.up")
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

  @ViewBuilder
  private var previewContent: some View {
    if case .loaded(url: _, document: let document) = viewModel.download {
      NavigationStack {
        SearchablePDFPreview(
          document: document,
          currentPage: $previewPage
        )
        .ignoresSafeArea(.container)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(viewModel.document.title)
      }
      // Preview is full-screen; other sheets keep `sheetZoomTransition` (iOS 26+) for detents.
      // Resolve the zoom source to the *tapped* page (mirrors the
      // PDFPagingPreview's per-page sources) so iPad zooms from whichever
      // peek the user picked, not always from the centred page.
      .backport.navigationTransitionZoom(
        sourceID: PDFPageZoomID(base: AnyHashable(TransitionID.doc), index: previewPage),
        in: namespace
      )
    }
  }

  var body: some View {
    @Bindable var viewModel = viewModel

    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 16) {
        DocumentPreview(
          document: viewModel.document,
          downloadState: viewModel.download,
          currentPage: $previewPage,
          transitionID: TransitionID.doc,
          transitionNamespace: namespace,
          // Set previewPage explicitly here so the destination's sourceID
          // (computed from previewPage) is in sync with showPreview before
          // the cover renders. The PDFPagingPreview also writes currentPage
          // through the binding, but relying on that propagation alone has
          // a one-frame race that can leave the zoom anchored on the wrong
          // page.
          onTap: previewEnabled
            ? { tappedIndex in
              previewPage = tappedIndex
              showPreview = true
            }
            : nil
        )
        .frame(maxWidth: .infinity)
        .accessibilityLabel(.localizable(.documentOpen))

        VStack(alignment: .leading, spacing: 16) {
          DocumentTitleView(
            title: viewModel.document.title,
            transitionID: .title,
            namespace: namespace,
            action: { activeFieldEdit = .title },
            enabled: store.userCanChange(document: viewModel.document)
          )
          .editPopover(
            forFieldEdit: .title,
            active: $activeFieldEdit,
            popoverSize: CGSize(width: 480, height: 240)
          ) {
            TitleEditSheet(viewModel: viewModel)
              .sheetZoomTransition(sourceID: TransitionID.title, in: namespace)
          }

          readOnlyExplanation

          detailAspects
            .animation(.spring(duration: 0.25), value: viewModel.document)

          VStack(alignment: .leading, spacing: 6) {
            Text(.localizable(.tags))
              .font(.caption2)
              .textCase(.uppercase)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.tail)

            DocumentTagsSection(
              tags: viewModel.document.tags.map { store.tags[$0] },
              action: {
                activeFieldEdit = .tags
              },
              transitionID: .tags,
              namespace: namespace,
              enabled: store.userCanChange(document: viewModel.document)
            )
            .editPopover(
              forFieldEdit: .tags,
              active: $activeFieldEdit,
              detents: [.medium, .large]
            ) {
              TagsEditSheet(viewModel: viewModel)
                .sheetZoomTransition(sourceID: TransitionID.tags, in: namespace)
            }
          }
        }
        .padding(.horizontal)
        .frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
        .frame(maxWidth: .infinity)
      }
      .padding(.bottom)
    }
    .refreshable {
      let model = viewModel
      async let document: () = model.loadDocument()
      async let metadata: () = model.loadMetadata()
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

    // The full PDF reader is content-heavy; on iPad a normal sheet renders as a
    // small centered form sheet that wastes most of the screen, so we promote
    // it to a full-screen cover on regular size class while keeping the sheet
    // (with its zoom transition + swipe-to-dismiss) on compact.
    .apply {
      if horizontalSizeClass == .regular {
        $0.fullScreenCover(isPresented: $showPreview) {
          previewContent
        }
      } else {
        $0.sheet(isPresented: $showPreview) {
          previewContent
        }
      }
    }

    .task {
      await viewModel.loadDocument()
      await viewModel.loadMetadata()
      try? await viewModel.loadSuggestions()
    }

    .onChange(of: routeManager.pendingRoute, initial: true, handlePendingRoute)
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

  /// Presents the per-field editor anchored to the source view. Renders as a
  /// popover on regular size class and as a sheet (with the supplied detents)
  /// on compact via `presentationCompactAdaptation(.sheet)`. The shared
  /// `active` enum drives a derived isPresented binding so deep-link routing
  /// and aspect taps both flow through one piece of state.
  ///
  /// `popoverSize` only affects the popover layer — sheets ignore it and
  /// honour the supplied detents instead.
  fileprivate func editPopover<Content: View>(
    forFieldEdit field: FieldEdit,
    active: Binding<FieldEdit?>,
    detents: Set<PresentationDetent> = [.medium, .large],
    popoverSize: CGSize = CGSize(width: 420, height: 520),
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    let isPresented = Binding(
      get: { active.wrappedValue == field },
      set: { newValue in
        if !newValue, active.wrappedValue == field {
          active.wrappedValue = nil
        }
      }
    )
    return popover(isPresented: isPresented) {
      content()
        .frame(idealWidth: popoverSize.width, idealHeight: popoverSize.height)
        .presentationDetents(detents)
        .presentationCompactAdaptation(.sheet)
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
      title: .localizable(.asn),
      label: .text(String(localized: .localizable(.documentAsn(42)))), systemImage: "qrcode")
    EditableAspect(
      title: .localizable(.correspondent),
      label: .text("Preview Correspondent"), systemImage: "person.fill")
    EditableAspect(
      title: .localizable(.documentType),
      label: .text("Preview Type"), systemImage: "doc.fill")
    EditableAspect(
      title: .localizable(.sortOrderOwner),
      label: .notAssigned, systemImage: "person.badge.key.fill")
    EditableAspect(
      title: .localizable(.sortOrderOwner),
      label: .private, systemImage: "person.badge.key.fill")

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
