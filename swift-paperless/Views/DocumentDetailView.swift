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

                GeometryReader { geometry in
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
                        AuthAsyncImage(url: URL(string: "\(API_BASE_URL)documents/\(document.id)/thumb/")) {
                            image in
                            ZStack {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, alignment: .top)
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray, lineWidth: 1))
                                    .opacity(previewLoading ? 0.6 : 1.0)

                                if previewLoading {
                                    ProgressView()
                                }
                            }.animation(.default, value: previewLoading)

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

            }.padding()
        }
        .refreshable {
//            Task {
            if let document = await store.getDocument(id: document.id) {
                self.document = document
            }
//            }
        }
        .toolbar {
            Button("Edit") {
                editing.toggle()
            }.sheet(isPresented: $editing) {
                DocumentEditView(document: $document)
            }
        }
//        .navigationTitle(
//            Text.titleCorrespondent(value: correspondent)
//                + Text("\(document.title)")
//        )
    }
}
