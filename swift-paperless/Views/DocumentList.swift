//
//  DocumentList.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.07.23.
//

import Foundation
import SwiftUI

struct LoadingDocumentList: View {
    @State private var documents: [Document] = []
    @StateObject private var store = DocumentStore(repository: PreviewRepository())

    var body: some View {
        VStack {
            ForEach(documents, id: \.self) { document in
                DocumentCell(document: document)
                    .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
                    .redacted(reason: .placeholder)
                Divider()
                    .padding(.horizontal)
            }
        }
        .environmentObject(store)
        .task {
            documents = await store.fetchDocuments(clear: true, pageSize: 10)
//            documents = await PreviewRepository().documents(filter: FilterState()).fetch(limit: 10)
        }
    }
}

struct DocumentList: View {
    @EnvironmentObject private var store: DocumentStore

    @Binding var documents: [Document]
    @State private var loadingMore = false

    struct Cell: View {
        @EnvironmentObject private var nav: NavigationCoordinator

        var store: DocumentStore
        var document: Document

        var body: some View {
            NavigationLink(value:
                NavigationState.detail(document: document)
            ) {
                DocumentCell(document: document)
                    .contentShape(Rectangle())

                    .padding(5)
                    .contextMenu {
                        Button {
                            nav.path.append(NavigationState.detail(document: document))
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                    } preview: {
                        Button {
                            print("open")
                        } label: {
                            DocumentPreview(store: store, document: document)
                        }
                    }
            }

            .padding(.horizontal, 10)
            .buttonStyle(.plain)

            Divider()
                .padding(.horizontal)
        }
    }

    func loadMore() async {
        let new = await store.fetchDocuments(clear: false, pageSize: 101)
        withAnimation {
            documents += new
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading) {
            ForEach(
                Array(zip(documents.indices, documents)), id: \.1.id
            ) { index, document in
                Cell(store: store, document: document)
                    .if(index > documents.count - 10) { view in
                        view.task {
                            let hasMore = await store.hasMoreDocuments()
                            print("Check more: has: \(hasMore), #doc \(documents.count)")
                            if !loadingMore && hasMore {
                                loadingMore = true
                                //                                    await load(false)
                                await loadMore()
                                loadingMore = false
                            }
                        }
                    }
            }
        }
//        }
    }
}
