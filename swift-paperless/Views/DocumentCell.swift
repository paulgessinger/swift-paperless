//
//  DocumentCell.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI

struct DocumentPreviewImage: View {
    var store: DocumentStore
    var document: Document

    var body: some View {
        AuthAsyncImage(image: {
            await store.repository.thumbnail(document: document)
        }) {
            image in
            image
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100, alignment: .top)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(.gray, lineWidth: 1))
        } placeholder: {
            Rectangle()
                .fill(Color(white: 0.8))
                .cornerRadius(10)
                .scaledToFit()
                .overlay(ProgressView())
        }
    }
}

struct DocumentCell: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.redactionReasons) var redactionReasons

    var document: Document
//    var correspondent: Correspondent? = nil
//    var documentType: DocumentType? = nil
//    var tags: [Tag] = []

    init(document: Document) {
        self.document = document
//        self.correspondent = nil
//        self.documentType = nil
//        self.tags = []
//        self.correspondent = self.document.correspondent.flatMap { store.correspondents[$0] }
//        self.documentType = self.document.documentType.flatMap { store.documentTypes[$0] }
//        self.tags = self.document.tags.compactMap { store.tags[$0] }
    }

    var body: some View {
        HStack(alignment: .top) {
            if redactionReasons.contains(.placeholder) {
                Rectangle()
                    .fill(Color(white: 0.8))
                    .cornerRadius(10)
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .shadow(color: Color("ImageShadow"), radius: 5)
            }
            else {
                DocumentPreviewImage(store: store,
                                     document: document)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color("ImageShadow"), radius: 5)
            }

            VStack(alignment: .leading) {
                if let id = document.correspondent, let name = store.correspondents[id]?.name {
                    Text("\(name):")
//                        .fixedSize()
                        .foregroundColor(.accentColor)
//                        .id("correspondent")
                }
                Text("\(document.title)")
//                    .fixedSize()
                    .bold()

                if let id = document.documentType, let name = store.documentTypes[id]?.name {
                    Text(name)
//                        .fixedSize()
                        .foregroundColor(Color.orange)
                }

                Text(document.created, style: .date)
//                    .fixedSize()

                TagsView(tags: document.tags.compactMap { store.tags[$0] })
                    .padding(0)
                    .transition(.opacity)
            }
            .padding(.horizontal, 5)
            .layoutPriority(1)
        }
//        .transaction { t in
//            t.animation = nil
//        }
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
            documents = await store.fetchDocuments(clear: false)
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
