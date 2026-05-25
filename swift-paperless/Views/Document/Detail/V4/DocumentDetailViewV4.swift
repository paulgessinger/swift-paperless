//
//  DocumentDetailViewV4.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.02.26.
//

import AppShared
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
  // iPad-only: drives the .inspector-presented edit panel. Defaults open so
  // the document's metadata is visible alongside the PDF the first time
  // someone opens it on iPad. SceneStorage so the open/closed state
  // persists across app launches per scene.
  @SceneStorage("DocumentDetailEditInspectorVisible") private var showEditInspector = true
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
    switch edit {
    case .none:
      activeFieldEdit = nil
      if activeSheet == .notes {
        activeSheet = nil
      }
    case .field(let field):
      if let fieldEdit = FieldEdit(field: field) {
        // Edit popovers anchor to rows inside the inspector on iPad. Force
        // it open so the deep link doesn't silently no-op when the user
        // had previously collapsed the inspector.
        if horizontalSizeClass == .regular {
          showEditInspector = true
        }
        activeFieldEdit = fieldEdit
      } else if field == .notes {
        activeSheet = .notes
      }
    case .all:
      if horizontalSizeClass == .regular {
        showEditInspector = true
      }
    case .close:
      if horizontalSizeClass == .regular {
        showEditInspector = false
      }
      activeFieldEdit = nil
      if activeSheet == .notes {
        activeSheet = nil
      }
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
      document.asn.map { .text(String(localized: .app(.documentAsn($0)))) } ?? .notAssigned
    // Inspector lays out one column so each aspect spans full width;
    // iPhone keeps the two-column pill layout.
    let columns: [GridItem] =
      horizontalSizeClass == .regular
      ? [GridItem(.flexible(), spacing: 12)]
      : [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
      ]
    return LazyVGrid(columns: columns, spacing: 12) {
      EditableAspect(
        title: .app(.asn),
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
        title: .app(.correspondent),
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
        title: .app(.documentType),
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
        title: .app(.documentEditCreatedDateLabel),
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
        title: .app(.storagePath),
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
        title: .app(.sortOrderOwner),
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
          .app(.documentReadOnlyNoGlobalPermission)
        } else if case .user(let ownerId) = document.owner, let owner = store.users[ownerId] {
          .app(.documentReadOnlyOwnedBy(owner.username))
        } else {
          .app(.documentReadOnlyNotOwner)
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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
      // iPad: match the SearchablePDFPreview search button — 13pt padding,
      // semibold .title2 icon, circular glass. Badge becomes a corner pill
      // overlay so the circle isn't stretched.
      Button(action: action) {
        HStack {
          Label(localized: label, systemImage: image)
            .font(.title2)
            .fontWeight(isRegular ? .semibold : .regular)
            .labelStyle(.iconOnly)
            .frame(width: iconSize, height: iconSize)

          if !isRegular, let badge {
            Text(badge)
          }
        }
        .padding(isRegular ? 13 : 10)
        .apply {
          if let transitionID, let namespace {
            $0.backport.matchedTransitionSource(id: transitionID, in: namespace)
          } else {
            $0
          }
        }
        .apply {
          if isRegular {
            $0.backport.glassEffect(.regular.interactive(), in: Circle())
          } else {
            $0.backport.glassEffect(.regular.interactive())
          }
        }
        .overlay(alignment: .topTrailing) {
          if isRegular, let badge {
            Text(badge)
              .font(.caption2)
              .fontWeight(.bold)
              .foregroundStyle(.white)
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(.red, in: Capsule())
              .offset(x: 6, y: -4)
          }
        }
      }
      .foregroundStyle(style)
    }
  }

  // The bare metadata/notes/delete buttons. Used inline on iPhone (inside
  // the `metadataBar` glass capsule) and on iPad as the trailing slot of
  // SearchablePDFPreview's bottom bar.
  @ViewBuilder
  private var metadataActionButtons: some View {
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
      label: deleted ? .app(.documentDeleted) : .app(.delete),
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
      String(localized: .app(.confirmationPromptTitle)),
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: .app(.delete)), role: .destructive) {
        deleteDocument()
      }
      Button(String(localized: .app(.cancel)), role: .cancel) {}
    }
  }

  @ViewBuilder
  private var metadataBar: some View {
    GlassEffectContainerCompat {
      HStack {
        metadataActionButtons
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
      Label(localized: .app(.shareLink), systemImage: "link")
    }

    if let url = viewModel.documentUrl {
      ShareLink(item: url) {
        Label(localized: .app(.documentLink), systemImage: "safari")
      }
    }

    Menu {
      let deepLinks = viewModel.deepLinks

      if let url = deepLinks.withoutServer?.url {
        ShareLink(item: url) {
          Text(.app(.documentDeepLinkWithoutBackend))
        }
      }

      if let url = deepLinks.withServer?.url {
        ShareLink(item: url) {
          Text(.app(.documentDeepLinkWithBackend))
        }
      }
    } label: {
      Label(localized: .app(.documentDeepLink), systemImage: "app")
    }

    Divider()

    let archiveURL: URL? =
      if case .loaded(url: let url, document: _) = viewModel.download { url } else { nil }
    let originalURL: URL? =
      if case .loaded(url: let url) = viewModel.originalDownload { url } else { nil }

    Menu {
      ShareLink(item: archiveURL ?? URL(filePath: "/")) {
        Label(localized: .app(.shareArchive), systemImage: "doc.zipper")
      }
      .disabled(archiveURL == nil)

      ShareLink(item: originalURL ?? URL(filePath: "/")) {
        Label(localized: .app(.shareOriginal), systemImage: "doc")
      }
      .disabled(originalURL == nil)
    } label: {
      Label(localized: .app(.shareDocument), systemImage: "square.and.arrow.up")
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
      .backport.navigationTransitionZoom(sourceID: TransitionID.doc, in: namespace)
    }
  }

  // The aspects/tags/title block. Used inline in the iPhone layout and
  // inside the iPad inspector. Popovers attach to their source views, so the
  // anchoring is the same whichever container hosts the panel.
  @ViewBuilder
  private var editPanel: some View {
    @Bindable var viewModel = viewModel
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
        Text(.app(.tags))
          .font(.caption2)
          .fontWeight(.semibold)
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
  }

  // iPhone layout: horizontal page preview + edit panel stacked in a scroll
  // view, metadata bar pinned to the bottom.
  @ViewBuilder
  private var compactBody: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 16) {
        DocumentPreview(
          document: viewModel.document,
          downloadState: viewModel.download,
          currentPage: $previewPage,
          transitionID: TransitionID.doc,
          transitionNamespace: namespace,
          onTap: previewEnabled ? { showPreview = true } : nil
        )
        .frame(maxWidth: .infinity)
        .accessibilityLabel(.app(.documentOpen))

        editPanel
          .padding(.horizontal)
      }
      .padding(.bottom)
    }
    .refreshable {
      let model = viewModel
      async let document: () = model.loadDocument()
      async let metadata: () = model.loadMetadata()
      _ = await (document, metadata)
    }
    .safeAreaInset(edge: .bottom) {
      metadataBar
    }
  }

  // iPad layout: full SearchablePDFPreview as the primary surface; the
  // metadata buttons are merged into the same bottom bar as the search
  // button. Edit panel goes into a resizable, togglable inspector.
  @ViewBuilder
  private var regularBody: some View {
    let pdfReady: Bool = {
      if case .loaded = viewModel.download { return true }
      return false
    }()

    // PDF mounts as soon as the document is loaded, with a scrim layered on
    // top until then. Animating the scrim's opacity is more reliable than
    // animating PDFKit's insertion — PDFView's own layout phase otherwise
    // races the SwiftUI fade and you end up seeing nothing.
    ZStack {
      if case .loaded(url: _, document: let pdfDocument) = viewModel.download {
        SearchablePDFPreview(
          document: pdfDocument,
          currentPage: $previewPage,
          showsDismissButton: false,
          extendsBehindTopBar: true
        ) {
          // Inject the metadata/notes/delete trio into the same row as the
          // search button so they share the bar's vertical position.
          HStack {
            metadataActionButtons
          }
        }
      }

      Color(.secondarySystemBackground)
        .ignoresSafeArea()
        .overlay {
          ProgressView()
            .controlSize(.large)
            .scaleEffect(1.0)
        }
        .opacity(pdfReady ? 0 : 1)
        .animation(.easeOut(duration: 0.35), value: pdfReady)
        .allowsHitTesting(!pdfReady)
    }
    .inspector(isPresented: $showEditInspector) {
      ScrollView {
        editPanel
          .padding()
      }
      .scrollBounceBehavior(.basedOnSize)
      // Resizable inspector. SwiftUI doesn't expose the user-set width as a
      // binding, so persisting the resize across launches isn't directly
      // possible — exposing min/ideal/max at least lets the user drag.
      .inspectorColumnWidth(min: 280, ideal: 360, max: 560)
    }
  }

  var body: some View {
    Group {
      if horizontalSizeClass == .regular {
        regularBody
      } else {
        compactBody
      }
    }
    .navigationTitle(String(localized: .app(.details)))
    .navigationBarTitleDisplayMode(.inline)

    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          shareMenuContent
        } label: {
          Label(localized: .app(.share), systemImage: "square.and.arrow.up")
            .labelStyle(.iconOnly)
        }
      }
      if horizontalSizeClass == .regular {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showEditInspector.toggle()
          } label: {
            Label(localized: .app(.edit), systemImage: "sidebar.right")
              .labelStyle(.iconOnly)
          }
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

    .sheet(isPresented: $showPreview) {
      previewContent
    }

    .task {
      await viewModel.loadDocument()
      await viewModel.loadMetadata()
      try? await viewModel.loadSuggestions()
    }

    .onChange(of: routeManager.pendingRoute, initial: true, handlePendingRoute)

    // External mutations (e.g. the document-list swipe action that strips
    // inbox tags) update the store but don't reach our local copy. Sync from
    // the server-confirmed event so the edit panel stays in lock-step.
    .onReceive(store.eventPublisher) { event in
      guard case .changeReceived(let updated) = event,
        updated.id == viewModel.document.id
      else { return }
      viewModel.document = updated
    }
  }
}

// MARK: - Helpers

/// One-frame-deferred wrapper that holds an empty placeholder of the
/// popover's ideal size during the very first render pass, then mounts the
/// real content on the next runloop tick. This prevents toolbar items and
/// `.searchable` from registering against the source view's parent
/// NavigationStack while the popover host is still being set up.
private struct DeferredPopoverContent<Content: View>: View {
  let size: CGSize
  @ViewBuilder let content: () -> Content
  @State private var ready = false

  var body: some View {
    Group {
      if ready {
        content()
      } else {
        Color.clear
      }
    }
    .frame(idealWidth: size.width, idealHeight: size.height)
    .task { ready = true }
  }
}

extension View {
  /// Applies `.zoom` navigation transition only on iOS 26+.
  /// On iOS 18, the zoom transition forces full-screen presentation which breaks sheet detent interaction.
  fileprivate func sheetZoomTransition(sourceID: some Hashable, in namespace: Namespace.ID)
    -> some View
  {
    apply {
      #if targetEnvironment(macCatalyst)
        $0
      #else
        if #available(iOS 26.0, *) {
          $0.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
          $0
        }
      #endif
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
      // SwiftUI evaluates the popover content closure once in the source's
      // environment before the popover host installs its own scope; during
      // that frame, the picker sheet's `.searchable` and `.toolbar` items
      // register preferences against the *parent column's* nav bar and
      // visibly merge with the share/inspector buttons until the popover
      // host takes over. Deferring the first render of `content()` past
      // that frame keeps those modifiers from running in the wrong scope.
      DeferredPopoverContent(size: popoverSize, content: content)
        #if !targetEnvironment(macCatalyst)
          .presentationDetents(detents)
          .presentationCompactAdaptation(.sheet)
        #endif
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
      title: .app(.asn),
      label: .text(String(localized: .app(.documentAsn(42)))), systemImage: "qrcode")
    EditableAspect(
      title: .app(.correspondent),
      label: .text("Preview Correspondent"), systemImage: "person.fill")
    EditableAspect(
      title: .app(.documentType),
      label: .text("Preview Type"), systemImage: "doc.fill")
    EditableAspect(
      title: .app(.sortOrderOwner),
      label: .notAssigned, systemImage: "person.badge.key.fill")
    EditableAspect(
      title: .app(.sortOrderOwner),
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
    .environment(RouteManager())
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
