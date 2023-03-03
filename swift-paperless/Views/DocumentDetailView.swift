//
//  DocumentDetailView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI

struct DocumentDetailView: View {
    @EnvironmentObject var store: DocumentStore

    @State private var editing = false
    @Binding var document: Document

    @State private var correspondent: Correspondent?
    @State private var documentType: DocumentType?

    @State private var previewUrl: URL?
    @State private var previewLoading = false
    @State private var tags: [Tag] = []

    func loadData() async {
        correspondent = nil
        documentType = nil
        if let cId = document.correspondent {
            correspondent = await store.getCorrespondent(id: cId)
        }
        if let dId = document.documentType {
            documentType = await store.getDocumentType(id: dId)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Group {
                    (
                        Text.titleCorrespondent(value: correspondent)
                            + Text("\(document.title)")
                    ).font(.title)
                }.task {
                    await loadData()
                }
                .onChange(of: document) { _ in
                    Task {
                        await loadData()
                    }
                }

                Text.titleDocumentType(value: documentType)
                    .font(.headline)
                    .foregroundColor(Color.orange)

                Text(document.created, style: .date)

                TagsView(tags: tags)
                    .task {
                        tags = await store.getTags(document.tags)
                    }

                Button(action: {
                    Task {
                        if previewLoading {
                            return
                        }
                        previewLoading = true
                        previewUrl = await getPreviewImage(documentID: document.id)
                        previewLoading = false
                    }
                }) {
                    AuthAsyncImage(image: {
                        await store.getImage(document: document)
                    }) {
                        image in
                        VStack {
                            ZStack {
                                image
                                    .resizable()
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray, lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    .scaledToFill()
                                    .opacity(previewLoading ? 0.6 : 1.0)

                                if previewLoading {
                                    ProgressView()
                                }
                            }
                            .animation(.default, value: previewLoading)
                        }

                    } placeholder: {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)
                .quickLookPreview($previewUrl)
            }
            .padding()
        }
        .refreshable {
            if let document = await store.getDocument(id: document.id) {
                self.document = document
            }
        }
        .toolbar {
            Button("Edit") {
                editing.toggle()
            }.sheet(isPresented: $editing) {
                DocumentEditView(document: $document)
            }
        }
    }
}

struct DocumentDetailsView_Previews: PreviewProvider {
    static let store = DocumentStore()

    static var document: Document = .init(id: 1689, added: "Hi",
                                          title: "Official ESTA Application Website, U.S. Customs and Border Protection",
                                          documentType: 2, correspondent: 2,
                                          created: Date.now, tags: [1, 2])

    static var previews: some View {
        DocumentDetailView(document: .constant(document))
            .environmentObject(store)
    }
}
