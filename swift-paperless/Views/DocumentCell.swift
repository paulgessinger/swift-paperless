//
//  DocumentCell.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI
import WrappingStack

struct DocumentCell: View {
    @EnvironmentObject var store: DocumentStore

    let document: Document

    @State private var correspondent: Correspondent?
    @State private var documentType: DocumentType?
    @State private var tags: [Tag] = []

    var body: some View {
        HStack(alignment: .top) {
            AuthAsyncImage(image: {
                await store.getImage(document: document)
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
                Rectangle().fill(.gray).scaledToFit().overlay(ProgressView())
            }
            .frame(width: 100, height: 100)
            VStack(alignment: .leading) {
                Group {
                    Text.titleCorrespondent(value: correspondent)
                        + Text("\(document.title)")
                }.task {
                    if let cId = document.correspondent {
                        correspondent = await store.getCorrespondent(id: cId)
                    }

                    if let dId = document.documentType {
                        documentType = await store.getDocumentType(id: dId)
                    }
                }

                Text.titleDocumentType(value: documentType)
                    .foregroundColor(Color.orange)

                Text(document.created, style: .date)

                TagsView(tags: tags)
                    .task {
                        tags = await store.getTags(document.tags)
                    }.padding(0)
            }
            .padding(.horizontal, 5)

//            Image(systemName: "chevron.right")
        }
    }
}

struct DocumentCell_Previews: PreviewProvider {
    static let store = DocumentStore()

    static var documents: [Document] = [
        .init(id: 1689, added: "Hi",
              title: "Official ESTA Application Website, U.S. Customs and Border Protection",
              documentType: 2, correspondent: 2,
              created: Date.now, tags: [1, 2]),
        .init(id: 1688, added: "Hi",
              title: "Official ESTA Application Website, U.S. Customs and Border Protection",
              documentType: 2, correspondent: 2,
              created: Date.now, tags: []),
    ]

    static var previews: some View {
        VStack {
            ForEach(documents, id: \.id) { document in
                DocumentCell(document: document)
                    .padding()
            }
        }
        .environmentObject(store)
    }
}
