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

    var document: Document

    @State private var correspondent: Correspondent?
    @State private var documentType: DocumentType?
    @State private var tags: [Tag]? = nil

    @State private var initial = true
    @State private var isLoading = false

    @Namespace private var animation

    func load() async {
        isLoading = true
        async let tagResult = store.getTags(document.tags)
        async let corrResult = document.correspondent == nil ? nil : store.getCorrespondent(id: document.correspondent!)
        async let typeResult = document.documentType == nil ? nil : store.getDocumentType(id: document.documentType!)

        let (tagR, corrR, typeR) = await (tagResult, corrResult, typeResult)

        if let (cached, corr) = corrR {
            if cached {
                correspondent = corr
            }
            else {
                withAnimation {
                    correspondent = corr
                }
            }
        }

        if let (cached, type) = typeR {
            if cached {
                documentType = type
            }
            else {
                withAnimation {
                    documentType = type
                }
            }
        }

        let (cached, tags) = tagR
        if cached {
            self.tags = tags
        }
        else {
            withAnimation {
                self.tags = tags
            }
        }

        withAnimation {
//            tags = tagR
//            correspondent = corrR?.1
//            documentType = typeR?.1
            isLoading = false
        }
    }

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

            VStack(alignment: .leading) {
                if isLoading || correspondent != nil {
                    let corr = correspondent?.name ?? "      "
                    Text("\(corr):")
                        .foregroundColor(.accentColor)
                        .redacted(reason: correspondent == nil ? .placeholder : [])
                        .id("correspondent")
                }
                Text("\(document.title)").bold()

                if let name = documentType?.name {
                    Text(name)
                        .fixedSize()
                        .foregroundColor(Color.orange)
                        .transition(.opacity)
//                        .id("documentType")
//                        .matchedGeometryEffect(id: "documentType", in: animation)
                }
                else if isLoading {
                    Text(" BLUBB ")
                        .fixedSize()
                        .foregroundColor(Color.orange)
                        .redacted(reason: documentType == nil ? .placeholder : [])
                        .transition(.opacity)
//                        .id("documentType_redacted")
//                        .matchedGeometryEffect(id: "documentType", in: animation)
                }

                Text(document.created, style: .date)

                TagsView(tags: tags ?? [])
                    .redacted(reason: documentType == nil ? .placeholder : [])
                    .padding(0)
                    .transition(.opacity)
            }
            .padding(.horizontal, 5)
        }
        .task {
            await load()
        }
    }
}

struct DocumentCell_Previews: PreviewProvider {
    static let store = DocumentStore()

    static var documents: [Document] = [
        .init(id: 1715,
              title: "Official ESTA Application Website, U.S. Customs and Border Protection",
              documentType: 2, correspondent: 2,
              created: Date.now, tags: [1, 2]),
        .init(id: 1714,
              title: "Official ESTA Application Website, U.S. Customs and Border Protection",
              documentType: 1, correspondent: nil,
              created: Date.now, tags: [1, 2]),
    ]

    static var previews: some View {
        VStack {
            ForEach(documents, id: \.id) { document in
                DocumentCell(document: document)
                    .padding()
            }
            Spacer()
        }
        .environmentObject(store)
    }
}
