//
//  DocumentCell.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

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

    .task {
      image.transaction = Transaction(animation: .linear(duration: 0.1))
      do {
        image.pipeline = store.imagePipeline
        try image.load(
          ImageRequest(
            urlRequest: store.repository.thumbnailRequest(document: document),
            processors: [.resize(width: 130)]))

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

  public init(document: Document, store: DocumentStore) {
    self.document = document
    self.store = store
  }

  public static var dateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.doesRelativeDateFormatting = false
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }

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
        .frame(width: 130, height: 170, alignment: .topLeading)
        .shadow(color: Color("ImageShadow"), radius: 5)
        .transaction { tx in
          tx.animation = nil
        }
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

        TagsView(tags: document.tags.map { store.tags[$0] })
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 5)
    }
  }
}

#Preview {
  @Previewable @State var store = DocumentStore(repository: TransientRepository())
  @Previewable @State var documents = [Document]()

  List {
    ForEach(documents, id: \.id) { document in
      DocumentCell(document: document, store: store)
    }
  }
  .task {
    do {
      let repository = store.repository as! TransientRepository
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

      try await store.fetchAll()
    } catch { print(error) }
  }
}
