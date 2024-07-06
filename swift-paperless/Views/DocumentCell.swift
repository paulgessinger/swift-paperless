//
//  DocumentCell.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import Nuke
import NukeUI
import os
import SwiftUI

struct DocumentPreviewImage: View {
    var store: DocumentStore
    var document: Document

    @StateObject private var image = FetchImage()

    var body: some View {
        VStack {
            image.image?
                .resizable()
                .scaledToFit()
        }

        .task {
            image.transaction = Transaction(animation: .linear(duration: 0.1))
            do {
                let dataloader = DataLoader()

                if let delegate = store.repository.delegate {
                    dataloader.delegate = delegate
                }

                image.pipeline = ImagePipeline(configuration: .init(dataLoader: dataloader))

                try image.load(ImageRequest(urlRequest: store.repository.thumbnailRequest(document: document), processors: [.resize(width: 130)]))
            } catch {
                Logger.shared.error("Error loading document thumbnail for cell: \(error)")
            }
        }
    }
}

struct DocumentCellAspect: View {
    var label: String
    var systemImage: String

    @ScaledMetric(relativeTo: .body) var imageWidth = 20.0

    init(_ label: String, systemImage: String) {
        self.label = label
        self.systemImage = systemImage
    }

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .frame(width: imageWidth)
            Text(label)
        }
    }
}

struct DocumentCell: View {
    var store: DocumentStore
    @Environment(\.redactionReasons) var redactionReasons

    var document: Document

    init(document: Document, store: DocumentStore) {
        self.document = document
        self.store = store
    }

    static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.doesRelativeDateFormatting = false
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    typealias Aspect = DocumentCellAspect

    var body: some View {
        HStack(alignment: .top) {
            if redactionReasons.contains(.placeholder) {
                Rectangle()
                    .fill(Color(white: 0.8))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.gray, lineWidth: 0.33))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(width: 130, height: 170, alignment: .topLeading)
                    .shadow(color: Color("ImageShadow"), radius: 5)
            } else {
                DocumentPreviewImage(store: store,
                                     document: document)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.gray, lineWidth: 0.33))
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

                if let id = document.correspondent, let name = store.correspondents[id]?.name {
                    Aspect(name, systemImage: "person")
                        .foregroundColor(.accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let id = document.documentType, let name = store.documentTypes[id]?.name {
                    Aspect(name, systemImage: "doc")
                        .foregroundColor(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let id = document.storagePath, let name = store.storagePaths[id]?.name {
                    Aspect(name, systemImage: "archivebox")
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Aspect(DocumentCell.dateFormatter.string(from: document.created), systemImage: "calendar")

                TagsView(tags: document.tags.compactMap { store.tags[$0] })
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 5)
        }
    }
}

private struct HelperView: View {
    @EnvironmentObject var store: DocumentStore
    @State var documents = [Document]()

    var body: some View {
        ScrollView(.vertical) {
            VStack {
                ForEach(documents.prefix(5), id: \.id) { document in
                    DocumentCell(document: document, store: store)
                }

                if let doc = documents.first {
                    DocumentCell(document: doc, store: store)
                        .redacted(reason: .placeholder)
                }
                Spacer()
            }
            .padding()
        }
        .task {
            // @TODO: Fix this preview
            if let documents = try? await store.repository.documents(filter: FilterState()).fetch(limit: 3) {
                self.documents = documents
            }
        }
    }
}

#Preview("DocumentCell") {
    let store = DocumentStore(repository: PreviewRepository())

    return HelperView()
        .environmentObject(store)
}

#Preview("DocumentCellRedacted") {
    let store = DocumentStore(repository: PreviewRepository())

    return HelperView()
        .redacted(reason: .placeholder)
        .environmentObject(store)
}
