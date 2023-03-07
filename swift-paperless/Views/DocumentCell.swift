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

    @State private var initial = true
    @State private var isLoading = false

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
                Rectangle()
                    .fill(.gray)
                    .cornerRadius(10)
                    .scaledToFit()
                    .overlay(ProgressView())
            }
            .frame(width: 100, height: 100)

            if !isLoading {
                VStack(alignment: .leading) {
                    Group {
                        if let corr = correspondent {
                            Text("\(corr.name):")
                                .foregroundColor(.accentColor)
                            //                            .transition(.opacity)
                        }
                        Text("\(document.title)").bold()
                    }
                    if let type = documentType {
                        Text(type.name)
                            .foregroundColor(Color.orange)
                    }

                    Text(document.created, style: .date)

                    TagsView(tags: tags)
                        .padding(0)
                    //                    .transition(.opacity)
                }
                .padding(.horizontal, 5)
                .transition(.opacity)
            }
            else {
                Spacer()
            }

//            Image(systemName: "chevron.right")
        }
        .task {
            if !initial {
                return
            }
            initial = false
            isLoading = true
            async let tagResult = store.getTags(document.tags)
            async let corrResult = document.correspondent == nil ? nil : store.getCorrespondent(id: document.correspondent!)
            async let typeResult = document.documentType == nil ? nil : store.getDocumentType(id: document.documentType!)

            let results = await (tagResult, corrResult, typeResult)

            tags = results.0
            correspondent = results.1
            documentType = results.2
            withAnimation {
                isLoading = false
            }
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
