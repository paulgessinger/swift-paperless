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
                    .frame(width: 150, height: 150, alignment: .top)
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray, lineWidth: 1))
            } placeholder: {
                Rectangle().fill(.gray).scaledToFit().overlay(ProgressView())
            }
            .frame(width: 150, height: 150)
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
                    }
            }
        }
    }
}

struct DocumentCell_Previews: PreviewProvider {
    static let store = DocumentStore()

    static var document: Document = .init(id: 1689, added: "Hi",
                                          title: "Official ESTA Application Website, U.S. Customs and Border Protection",
                                          documentType: 2, correspondent: 2,
                                          created: Date.now, tags: [1, 2])

    static var previews: some View {
        DocumentCell(document: document)
            .padding()
            .environmentObject(store)
    }
}
