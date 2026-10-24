//
//  DocumentCell.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import AppShared
import Common
import DataModel
import Networking
import Nuke
import NukeUI
import SwiftUI
import os

public struct DocumentPreviewImage: View {
  public var store: DocumentStore
  public var document: Document

  public init(store: DocumentStore, document: Document) {
    self.store = store
    self.document = document
  }

  @StateObject private var image = FetchImage()

  public var body: some View {
    VStack {
      image.image?
        .resizable()
        .scaledToFit()
    }

    // Keyed on the version, not bare: a bare `.task` runs once per view
    // identity, and a list refresh swaps in a new `Document` at the same row
    // position without changing that identity — so a version added or deleted
    // server-side would keep showing the thumbnail from the first load.
    // `versionQueryID` is exactly what `thumbnailRequest` puts in the URL, and
    // the version is what the request is keyed by, so this re-fires when the
    // request would change and never otherwise.
    .task(id: document.versionQueryID) {
      image.transaction = Transaction(animation: .linear(duration: 0.1))
      do {
        image.pipeline = store.imagePipeline
        try image.load(
          store.thumbnailImageRequest(for: document, processors: [.resize(width: 130)]))

        store.preloadThumbnail(for: document)
      } catch {
        Logger.shared.error("Error loading document thumbnail for cell: \(error)")
      }
    }
  }
}

public struct DocumentCellAspect: View {
  public var label: String?
  public var systemImage: String

  @ScaledMetric(relativeTo: .body) public var imageWidth = 20.0

  public init(localized: LocalizedStringResource, systemImage: String) {
    self.label = String(localized: localized)
    self.systemImage = systemImage
  }

  public init(_ label: String?, systemImage: String) {
    self.label = label
    self.systemImage = systemImage
  }

  public var body: some View {
    HStack {
      Image(systemName: systemImage)
        .frame(width: imageWidth)
      Text(label ?? String(localized: .permissions(.private)))
        .italic(label == nil)
    }
  }
}

public struct DocumentCell: View {
  public var store: DocumentStore
  @Environment(\.redactionReasons) public var redactionReasons

  public var document: Document

  /// Hides the inbox tags and shows a spinner in their place while their
  /// removal is in flight.
  public var isRemovingInboxTags: Bool

  /// Draws the kept-offline badge on the thumbnail when the document is kept.
  public var showsKeptOfflineBadge: Bool

  public init(
    document: Document, store: DocumentStore, showsKeptOfflineBadge: Bool = false,
    isRemovingInboxTags: Bool = false
  ) {
    self.document = document
    self.store = store
    self.showsKeptOfflineBadge = showsKeptOfflineBadge
    self.isRemovingInboxTags = isRemovingInboxTags
  }

  private var displayedTags: [Tag?] {
    let tags = document.tags.map { store.tags[$0] }
    guard isRemovingInboxTags else { return tags }
    return tags.filter { $0?.isInboxTag != true }
  }

  // Built once: a computed property here allocated a fresh DateFormatter on
  // every cell body evaluation, and every visible row pays that on each list
  // re-render. `autoupdatingCurrent` so a region-format change while the app
  // is alive still reaches it, as the per-render formatter used to.
  @MainActor
  public static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale.autoupdatingCurrent
    formatter.doesRelativeDateFormatting = false
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter
  }()

  public typealias Aspect = DocumentCellAspect

  public var body: some View {
    HStack(alignment: .top) {
      if redactionReasons.contains(.placeholder) {
        Rectangle()
          .fill(Color(white: 0.8))
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(.gray, lineWidth: 0.33)
          )
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          .frame(width: 130, height: 170, alignment: .topLeading)
          .shadow(color: Color("ImageShadow"), radius: 5)
      } else {
        DocumentPreviewImage(
          store: store,
          document: document
        )
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(.gray, lineWidth: 0.33)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color("ImageShadow"), radius: 5)
        // On the image, not the frame: a page narrower than the frame left
        // the badge hanging off its edge. The transaction below keeps it from
        // riding along with the image's animations.
        .overlay(alignment: .topTrailing) {
          if showsKeptOfflineBadge {
            KeptOfflineBadge(store: store, documentID: document.id)
          }
        }
        .transaction { tx in
          tx.animation = nil
        }
        .frame(width: 130, height: 170, alignment: .topLeading)
      }

      VStack(alignment: .leading) {
        Text(document.title)
          .bold()
          .fixedSize(horizontal: false, vertical: true)
          .lineLimit(2)
          .truncationMode(.middle)

        if let asn = document.asn {
          Aspect("#\(asn)", systemImage: "qrcode")
        }

        if let id = document.correspondent {
          Aspect(store.correspondents[id]?.name, systemImage: "person")
            .foregroundColor(.accentColor)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(1)
            .truncationMode(.tail)
        }

        if let id = document.documentType {
          Aspect(store.documentTypes[id]?.name, systemImage: "doc")
            .foregroundColor(Color.orange)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(1)
            .truncationMode(.tail)
        }

        if let pageCount = document.pageCount {
          Aspect(localized: .app(.pages(pageCount)), systemImage: "book.pages")
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(1)
            .truncationMode(.tail)
        }

        if document.notes.count > 0 {
          Aspect(localized: .app(.notes(document.notes.count)), systemImage: "note.text")
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(1)
            .truncationMode(.tail)
        }

        if let id = document.storagePath {
          Aspect(store.storagePaths[id]?.name, systemImage: "archivebox")
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(1)
            .truncationMode(.tail)
        }

        if case .user(let id) = document.owner {
          Aspect(store.users[id]?.username, systemImage: "person.badge.key")
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(1)
            .truncationMode(.tail)
        }

        Aspect(DocumentCell.dateFormatter.string(from: document.created), systemImage: "calendar")

        TagsView(tags: displayedTags, action: nil) {
          if isRemovingInboxTags {
            ProgressView()
              .controlSize(.small)
              .transition(.opacity)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 5)
    }
  }
}

#Preview {
  @Previewable @State var store = DocumentStore.preview(TransientRepository())
  @Previewable @State var documents = [Document]()

  List {
    ForEach(documents, id: \.id) { document in
      DocumentCell(document: document, store: store)
    }
  }
  .task {
    do {
      let repository = store.previewRepository(as: TransientRepository.self)
      repository.addUser(User(id: 1, isSuperUser: false, username: "user1", groups: []))
      try? repository.login(userId: 1)

      let correspondent = try await store.repository.create(
        correspondent: ProtoCorrespondent(name: "Test Correspondent"))
      let documentType = try await store.repository.create(
        documentType: ProtoDocumentType(name: "Test Document Type"))
      let storagePath = try await store.repository.create(
        storagePath: ProtoStoragePath(name: "Test Storage Path"))
      let tag = try await store.repository.create(tag: ProtoTag(name: "Test Tag"))

      try await store.repository.create(
        document: ProtoDocument(
          title: "blubb", asn: 123, documentType: documentType.id, correspondent: correspondent.id,
          tags: [tag.id], storagePath: storagePath.id),
        file: #URL("http://example.com"), filename: "blubb.pdf")

      guard var document = repository.allDocuments().first else {
        print("DID NOT GET DOCUMENT")
        return
      }
      document.owner = .user(1)
      _ = try await repository.update(document: document)

      try await store.repository.create(
        document: ProtoDocument(title: "another", correspondent: correspondent.id),
        file: #URL("http://example.com"), filename: "blubb.pdf")
      try await store.repository.create(
        document: ProtoDocument(title: "A third", correspondent: correspondent.id),
        file: #URL("http://example.com"), filename: "blubb.pdf")

      documents = try await store.repository.documents(filter: .default).fetch(limit: 100_000)

      try await store.sync()
    } catch { print(error) }
  }
}

/// The kept-offline badge, for a document kept on its own or by a kept saved
/// view. It reads the kept state itself, so a toggle updates only the badge:
/// re-running the row's body rebuilt its swipe and menu actions, and the row
/// closing its swipe was drawn below its place.
/// Always in the tree and only shown or hidden, for the same reason, with
/// its spring scoped to the kept state.
private struct KeptOfflineBadge: View {
  let store: DocumentStore
  let documentID: UInt

  var body: some View {
    let isKept = store.isOnDevice(documentID)
    Image(systemName: "arrow.down.circle.fill")
      .symbolRenderingMode(.palette)
      .foregroundStyle(.white, .indigo)
      .font(.title2)
      .shadow(color: Color("ImageShadow"), radius: 2)
      .padding(5)
      .scaleEffect(isKept ? 1 : 0.4)
      .opacity(isKept ? 1 : 0)
      .animation(.spring(duration: 0.35, bounce: 0.45), value: isKept)
      .accessibilityHidden(!isKept)
      .accessibilityLabel(Text(.app(.keptOffline)))
  }
}
