//
//  DocumentDetailView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI

private enum DownloadState {
    case initial
    case loading
    case loaded(URL)
    case ready(URL, Image)
    case error
}

struct DocumentDetailView: View {
    @EnvironmentObject var store: DocumentStore

    @State private var editing = false
    @State var document: Document

    @State private var correspondent: Correspondent?
    @State private var documentType: DocumentType?

    @State private var download: DownloadState = .initial
    @State private var previewUrl: URL?

    @State private var tags: [Tag] = []

    @State private var relatedDocuments: [Document]? = nil

    private func loadData() async {
        correspondent = nil
        documentType = nil
        if let cId = document.correspondent {
            correspondent = await store.getCorrespondent(id: cId)?.1
        }
        if let dId = document.documentType {
            documentType = await store.getDocumentType(id: dId)?.1
        }
        (_, tags) = await store.getTags(document.tags)
    }

    private func loadDocument() async {
        switch download {
        case .initial:
            download = .loading
            guard let url = await store.repository.download(documentID: document.id) else {
                download = .error
                return
            }
            download = .loaded(url)
            guard let image = pdfPreview(url: url) else {
                download = .error
                return
            }
            withAnimation {
                download = .ready(url, image)
            }

        default:
            break
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

                Divider()

                Button(action: {
                    Task {
                        if case let .ready(url, _) = download {
                            previewUrl = url
                        }
                    }
                }) {
                    switch download {
                    case .loading, .initial, .loaded:
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .frame(height: 400)
                    case .error:
                        HStack {
                            Spacer()
                            Label("Unable to load preview", systemImage: "eye.slash")
                                .labelStyle(.iconOnly)
                                .imageScale(.large)

                            Spacer()
                        }
                        .frame(height: 400)

                    case let .ready(_, image):
                        image
                            .resizable()
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .scaledToFill()
                            .shadow(color: Color(white: 0.9), radius: 5)
                    }
                }
                .buttonStyle(.plain)
                .quickLookPreview($previewUrl)

                if let related = relatedDocuments {
                    Group {
                        Divider()
                        HStack {
                            Spacer()
                            Text("Related documents")
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        ForEach(related) { _ in Text("Doc") }
                    }
                    .transition(
                        .opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding()
        }
        .task {
            await loadDocument()

            do {
                try await Task.sleep(for: .seconds(2))
                withAnimation {
                    relatedDocuments = []
                }
            }
            catch {}
        }

        .onChange(of: store.documents) { _ in
            if let document = store.documents[document.id] {
                self.document = document
            }
//            else {
//                print("Document in detail view went away")
//            }
        }

        .refreshable {
            if let document = await store.document(id: document.id) {
                self.document = document
            }
        }
        .toolbar {
            Button("Edit") {
                editing.toggle()
            }.sheet(isPresented: $editing) {
                DocumentEditView(document: document)
            }
        }
    }
}

private struct PreviewHelper: View {
    @EnvironmentObject var store: DocumentStore
    @State var document: Document?

    var body: some View {
        VStack {
            if let document = document {
                DocumentDetailView(document: document)
            }
        }
        .task {
            document = await store.document(id: 1)
        }
    }
}

struct DocumentDetailsView_Previews: PreviewProvider {
    static let store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        PreviewHelper()
            .environmentObject(store)
    }
}
