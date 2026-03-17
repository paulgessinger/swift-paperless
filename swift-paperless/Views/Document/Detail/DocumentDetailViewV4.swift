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

extension Common.SchemeToken where Value == Color {
  fileprivate static var editButtonColor: Self {
    .init(light: Color(white: 0.3), dark: Color(white: 0.5))
  }

  fileprivate static var backgroundColor: Self {
    .init(light: Color(white: 0.97), dark: Color(white: 0.2))
  }
}

private enum TransitionID: Hashable {
  case doc
  case tags
  case date
  case asn
  case correspondent
  case documentType
  case storagePath
  case owner
  case metadata
  case notes
}

private struct EditableAspect: View {
  let label: String?
  let systemImage: String
  let transitionID: TransitionID?
  let namespace: Namespace.ID?
  let action: (() -> Void)?

  @ScaledMetric(relativeTo: .body)
  private var fontSizeRaw = 15

  private var fontSize: CGFloat {
    min(fontSizeRaw, 20)
  }

  private var pillPadding: CGFloat {
    1 + fontSize / 6
  }

  private var iconPadding: CGFloat {
    2 + fontSize / 6
  }

  @SchemeValue(.backgroundColor)
  private var backgroundColor

  @SchemeValue(light: Color(white: 0.9), dark: Color(white: 0.35))
  private var iconBackgroundColor: Color

  @SchemeValue(.editButtonColor)
  private var editButtonColor

  init(
    localized: LocalizedStringResource, systemImage: String, action: (() -> Void)? = nil,
    transitionID: TransitionID? = nil,
    namespace: Namespace.ID? = nil
  ) {
    self.label = String(localized: localized)
    self.systemImage = systemImage
    self.action = action
    self.transitionID = transitionID
    self.namespace = namespace
  }

  init(
    _ label: String?, systemImage: String, action: (() -> Void)? = nil,
    transitionID: TransitionID? = nil,
    namespace: Namespace.ID? = nil
  ) {
    self.label = label
    self.systemImage = systemImage
    self.action = action
    self.transitionID = transitionID
    self.namespace = namespace
  }

  var body: some View {
    Button {
      action?()
    } label: {
      HStack {
        Image(systemName: systemImage)
          .resizable()
          .scaledToFit()
          .frame(width: fontSize, height: fontSize)
          .padding(iconPadding)
          .background(Circle().fill(iconBackgroundColor))
          .padding(.vertical, pillPadding)
          .padding(.leading, pillPadding)
        Text(label ?? String(localized: .permissions(.private)))
        Image(systemName: "pencil")
          .foregroundStyle(editButtonColor)
          .padding(.trailing, 2 + fontSize / 2)
      }
      .font(.system(size: fontSize))
      .background {
        Capsule()
          .fill(backgroundColor)
      }
      .dynamicTypeSize(...DynamicTypeSize.large)
      .apply {
        if let transitionID, let namespace {
          $0.backport.matchedTransitionSource(id: transitionID, in: namespace)
        } else {
          $0
        }
      }
    }
    .buttonStyle(.plain)
  }
}

private struct DocumentTagsSection: View {
  @SchemeValue(.editButtonColor)
  private var editButtonColor

  @SchemeValue(.backgroundColor)
  private var backgroundColor

  @SchemeValue(light: Color(white: 0.9), dark: Color(white: 0.3))
  private var editButtonBackground

  let tags: [Tag?]
  let action: (() -> Void)?
  let transitionID: TransitionID?
  let namespace: Namespace.ID?

  var body: some View {
    HStack(alignment: .top) {
      Button {
        action?()
      } label: {
        TagsView(
          tags: tags, action: nil,
          content: {
            Label(.localizable(.edit), systemImage: "pencil")
              .foregroundStyle(editButtonColor)
              .apply {
                if tags.isEmpty {
                  $0.labelStyle(.titleAndIcon)
                    .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                } else {
                  $0.labelStyle(.iconOnly)
                    .padding(5)
                }
              }
              .background {
                if tags.isEmpty {
                  Capsule()
                    .fill(backgroundColor)
                } else {
                  Circle()
                    .fill(backgroundColor)
                }
              }
          }
        )
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .dynamicTypeSize(...DynamicTypeSize.large)
    .apply {
      if let transitionID, let namespace {
        $0.backport.matchedTransitionSource(id: transitionID, in: namespace)
      } else {
        $0
      }
    }
  }
}

@MainActor
struct DocumentDetailViewV4: DocumentDetailViewProtocol {
  @State private var viewModel: DocumentDetailModel
  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController

  @State private var showEditSheet = false
  @State private var showMetadataSheet = false
  @State private var showNotesSheet = false
  @State private var showShareLinkSheet = false

  @State private var showTagsSheet = false
  @State private var showAsnSheet = false
  @State private var showCorrespondentSheet = false
  @State private var showDocumentTypeSheet = false
  @State private var showDateSheet = false
  @State private var showStoragePathSheet = false
  @State private var showOwnerSheet = false

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

  private var metadataActions: some View {
    HStack(spacing: 12) {
      Button {
        showEditSheet = true
      } label: {
        Label(localized: .localizable(.edit), systemImage: "square.and.pencil")
      }
      .buttonStyle(.borderedProminent)
    }
  }

  private var detailAspects: some View {
    let document = viewModel.document
    return HFlow(itemSpacing: 12) {
      if let asn = document.asn {
        EditableAspect(
          localized: .localizable(.documentAsn(asn)),
          systemImage: "qrcode",
          action: {
            showAsnSheet = true
          },
          transitionID: .asn,
          namespace: namespace
        )
      }

      if let id = document.correspondent {
        EditableAspect(
          store.correspondents[id]?.name,
          systemImage: "person.fill",
          action: {
            showCorrespondentSheet = true
          },
          transitionID: .correspondent,
          namespace: namespace
        )
      }

      if let id = document.documentType {
        EditableAspect(
          store.documentTypes[id]?.name,
          systemImage: "doc.fill",
          action: {
            showDocumentTypeSheet = true
          },
          transitionID: .documentType,
          namespace: namespace
        )
      }

      EditableAspect(
        DocumentCell.dateFormatter.string(from: document.created),
        systemImage: "calendar",
        action: {
          showDateSheet = true
        },
        transitionID: .date,
        namespace: namespace
      )

      if let id = document.storagePath {
        EditableAspect(
          store.storagePaths[id]?.name,
          systemImage: "archivebox.fill",
          action: {
            showStoragePathSheet = true
          },
          transitionID: .storagePath,
          namespace: namespace
        )
      }

      if case .user(let id) = document.owner {
        EditableAspect(
          store.users[id]?.username,
          systemImage: "person.badge.key.fill",
          action: {
            showOwnerSheet = true
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
            showMetadataSheet = true
          },
          transitionID: .metadata,
          namespace: namespace
        )

        BottomBarButton(
          label: .documentMetadata(.notes), image: "note.text",
          action: {
            showNotesSheet = true
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
      showShareLinkSheet = true
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
            .backport.matchedTransitionSource(id: TransitionID.doc, in: namespace)
            .accessibilityLabel(.localizable(.documentOpen))
        }
        .disabled(!previewEnabled)

        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .shadow(color: Color(.imageShadow), radius: 15)

        VStack(alignment: .leading, spacing: 0) {
          Text(viewModel.document.title)
            .font(.title)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .leading)

          if let pageCount = viewModel.document.pageCount {
            Label(.localizable(.pages(pageCount)), systemImage: "book.pages.fill")
              .font(.footnote)
              .italic()
          }

        }

        detailAspects

        DocumentTagsSection(
          tags: viewModel.document.tags.map { store.tags[$0] },
          action: {
            showTagsSheet = true
          },
          transitionID: .tags,
          namespace: namespace
        )

        metadataActions
      }
      .padding()
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

    .sheet(isPresented: $showTagsSheet) {
      TagsEditSheet(viewModel: viewModel)
        .backport.navigationTransitionZoom(sourceID: TransitionID.tags, in: namespace)
    }

    .sheet(isPresented: $showAsnSheet) {
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
      .backport.navigationTransitionZoom(sourceID: TransitionID.asn, in: namespace)
      .presentationDetents([.medium])
    }

    .sheet(isPresented: $showCorrespondentSheet) {
      NavigationStack {
        Text("Correspondent")
          .navigationTitle("Correspondent")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              CancelIconButton()
            }
          }
      }
      .backport.navigationTransitionZoom(sourceID: TransitionID.correspondent, in: namespace)
      .presentationDetents([.medium])
    }

    .sheet(isPresented: $showDocumentTypeSheet) {
      NavigationStack {
        Text("Document Type")
          .navigationTitle("Document Type")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              CancelIconButton()
            }
          }
      }
      .backport.navigationTransitionZoom(sourceID: TransitionID.documentType, in: namespace)
      .presentationDetents([.medium])
    }

    .sheet(isPresented: $showDateSheet) {
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
      .backport.navigationTransitionZoom(sourceID: TransitionID.date, in: namespace)
      .presentationDetents([.medium])
    }

    .sheet(isPresented: $showStoragePathSheet) {
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
      .backport.navigationTransitionZoom(sourceID: TransitionID.storagePath, in: namespace)
      .presentationDetents([.medium])
    }

    .sheet(isPresented: $showOwnerSheet) {
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
      .backport.navigationTransitionZoom(sourceID: TransitionID.owner, in: namespace)
      .presentationDetents([.medium])
    }

    .sheet(isPresented: $showMetadataSheet) {
      DocumentMetadataView(document: $viewModel.document, metadata: $viewModel.metadata)
        .environmentObject(store)
        .environmentObject(errorController)
        .backport.navigationTransitionZoom(
          sourceID: TransitionID.metadata, in: namespace)
    }
    .sheet(isPresented: $showNotesSheet) {
      DocumentNoteView(document: $viewModel.document)
        .environmentObject(store)
        .environmentObject(errorController)
        .backport.navigationTransitionZoom(
          sourceID: TransitionID.notes, in: namespace)
    }
    .sheet(isPresented: $showShareLinkSheet) {
      ShareLinkView(document: viewModel.document)
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
        .backport.navigationTransitionZoom(sourceID: TransitionID.doc, in: namespace)
      }
    }

    .task {
      await viewModel.loadDocument()
      await viewModel.loadMetadata()
    }
  }
}

private struct TagsEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController

  @Environment(\.dismiss) private var dismiss

  @State private var tagIds: [UInt] = []
  @State private var searchText = ""
  @State private var saving = false

  @Namespace private var tagNamespace

  private var availableTags: [Tag] {
    let search = searchText.lowercased()
    return store.tags.values
      .filter { !tagIds.contains($0.id) }
      .filter { search.isEmpty || $0.name.lowercased().contains(search) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func save() {
    Task {
      do {
        saving = true
        var document = viewModel.document
        document.tags = tagIds
        let updated = try await store.updateDocument(document)
        viewModel.document = updated
        saving = false
        dismiss()
      } catch {
        saving = false
        errorController.push(error: error)
      }
    }
  }
  
  let animation = Animation.spring(duration: 0.2)

  var body: some View {
    NavigationStack {
      List {
        Section {
          HFlow {
            ForEach(tagIds, id: \.self) { tagId in
              if let tag = store.tags[tagId] {
                Button {
                  withAnimation(animation) {
                    tagIds.removeAll { $0 == tagId }
                  }
                } label: {
                  HStack(spacing: 4) {
                    Text(tag.name)
                    Image(systemName: "xmark")
                      .font(.caption2)
                      .fontWeight(.bold)
                  }
                  .fixedSize()
                  .font(.body)
                  .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 6))
                  .background(tag.color.color)
                  .foregroundColor(tag.textColor.color)
                  .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: tagId, in: tagNamespace)
              }
            }
          }
          .frame(minHeight: 60, alignment: .topLeading)
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .listSectionSpacing(.compact)

        Section {
          ForEach(availableTags) { tag in
            Button {
              withAnimation(animation) {
                tagIds.append(tag.id)
              }
            } label: {
              HStack {
                TagView(tag: tag)
                  .fixedSize()
                  .matchedGeometryEffect(id: tag.id, in: tagNamespace)
                Spacer()
                Image(systemName: "plus")
                  .foregroundStyle(.secondary)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        } header: {
          if tagIds.isEmpty && searchText.isEmpty {
            Text(.localizable(.tags))
          }
        }
      }
      
      .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
      .navigationTitle(.localizable(.tags))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CancelIconButton()
        }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          } else {
            SaveButton {
              save()
            }
            .fontWeight(.bold)
            .disabled(tagIds == viewModel.document.tags)
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .interactiveDismissDisabled(tagIds != viewModel.document.tags)
    .onAppear {
      tagIds = viewModel.document.tags
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
