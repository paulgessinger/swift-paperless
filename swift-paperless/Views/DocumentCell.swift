//
//  DocumentCell.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import NukeUI
import SwiftUI

struct DocumentPreviewImage: View {
    var store: DocumentStore
    var document: Document

    @StateObject private var image = FetchImage()

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(white: 0.8))
//                .aspectRatio(contentMode: .fill)
                .overlay(ProgressView())
//                .frame(width: 100, height: 150, alignment: .top)

            image.image?
                .resizable()
//                .aspectRatio(contentMode: .fill)
//                .frame(width: 100, height: 150, alignment: .top)
        }

        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(.gray, lineWidth: 0.33))

        .task {
            guard let data = await store.repository.thumbnailData(document: document) else {
                return
            }

            image.load(ImageRequest(id: "\(document.id)", data: { data }, processors: [
                .resize(size: CGSize(width: 200, height: 200))
            ]))
        }

        .transition(.opacity)
        .animation(.default, value: image.image)
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
    @EnvironmentObject var store: DocumentStore
    @Environment(\.redactionReasons) var redactionReasons

    var document: Document

    init(document: Document) {
        self.document = document
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
                    .cornerRadius(10)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .shadow(color: Color("ImageShadow"), radius: 5)
            }
            else {
                DocumentPreviewImage(store: store,
                                     document: document)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .shadow(color: Color("ImageShadow"), radius: 5)
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
                    .padding(0)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .padding(.horizontal, 5)
        }
        .frame(height: 200)
    }
}

private struct HelperView: View {
    @EnvironmentObject var store: DocumentStore
    @State var documents = [Document]()

    var body: some View {
        VStack {
            ForEach(documents.prefix(5), id: \.id) { document in
                DocumentCell(document: document)
                    .padding()
            }
            Spacer()
        }
        .task {
            // @TODO: Fix this preview
//            documents = await store.fetchDocuments(clear: true, filter: FilterState())
        }
    }
}

struct DocumentCell_Previews: PreviewProvider {
    static let store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        HelperView()
            .environmentObject(store)
    }
}

struct DocumentCellRedacted_Previews: PreviewProvider {
    static let store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        HelperView()
            .redacted(reason: .placeholder)
            .environmentObject(store)
    }
}
