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
            List(documents, id: \.self) { document in
                VStack {
                    DocumentCell(document: document)
                        .redacted(reason: .placeholder)
                        .padding(.horizontal)
                        .padding(.vertical)
                    Rectangle()
                        .fill(.gray)
                        .frame(height: 0.33)
                        .padding(.horizontal)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            .listStyle(.plain)
        }
        .environmentObject(store)
        .task {
//            documents = await store.fetchDocuments(clear: true, filter: FilterState(), pageSize: 10)
            documents = await PreviewRepository().documents(filter: FilterState()).fetch(limit: 10)
        }
    }
}

class DocumentListViewModel: ObservableObject {
    private var store: DocumentStore
    private var filterState: FilterState

    @Published var documents: [Document] = []
    @Published var loading = false
    @Published var ready = false

    private var source: DocumentSource

    private var initialBatchSize: UInt = 20
    private var batchSize: UInt = 100
    private var fetchMargin = 10

    init(store: DocumentStore, filterState: FilterState) {
        self.store = store
        self.filterState = filterState
        self.source = store.repository.documents(filter: filterState)
    }

    @MainActor
    func load() async {
        guard documents.isEmpty && !loading else { return }
        loading = true
        let batch = await source.fetch(limit: initialBatchSize)
        documents = batch
        ready = true
        loading = false
    }

    @MainActor
    func fetchMoreIfNeeded(currentIndex: Int) async {
        if currentIndex >= documents.count - fetchMargin {
            guard !loading else { return }
            loading = true
            let batch = await source.fetch(limit: batchSize)
            documents += batch
            loading = false
        }
    }

    @MainActor
    func refresh(filter: FilterState? = nil, retain: Bool = false) async {
        if let filter {
            filterState = filter
        }
        source = store.repository.documents(filter: filterState)
        let batch = await source.fetch(limit: retain ? UInt(documents.count) : initialBatchSize)
        documents = batch
    }

    @MainActor
    func removed(document: Document) {
        documents.removeAll(where: { $0.id == document.id })
    }

    @MainActor
    func updated(document: Document) {
        if let target = documents.firstIndex(where: { $0.id == document.id }) {
            documents[target] = document
        }
    }
}

struct DocumentList: View {
    var store: DocumentStore
    @Binding var navPath: NavigationPath
    @Binding var filterState: FilterState

    @StateObject private var viewModel: DocumentListViewModel

    init(store: DocumentStore, navPath: Binding<NavigationPath>, filterState: Binding<FilterState>) {
        self.store = store
        self._navPath = navPath
        self._filterState = filterState
        self._viewModel = StateObject(wrappedValue: DocumentListViewModel(store: store, filterState: filterState.wrappedValue))
    }

    struct Cell: View {
        var store: DocumentStore
        var document: Document
        @Binding var navPath: NavigationPath

        var body: some View {
            ZStack {
                VStack {
                    DocumentCell(document: document)
                        .contentShape(Rectangle())

                        .padding(.horizontal)
                        .padding(.vertical)
                        .contextMenu {
                            Button {
                                navPath.append(NavigationState.detail(document: document))
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
                    Rectangle()
                        .fill(.gray)
                        .frame(height: 0.33)
                        .padding(.horizontal)
                }
//                    .padding(.horizontal, 10)

                NavigationLink(value:
                    NavigationState.detail(document: document)
                ) {}
                    .frame(width: 0)
                    .opacity(0)
            }

            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

//            Divider()
//                .padding(.horizontal)
//                .padding(.vertical, 0)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack {
                if !viewModel.ready {
                    LoadingDocumentList()
                }
                else {
                    let documents = viewModel.documents
                    if !documents.isEmpty {
                        List(
                            Array(zip(documents.indices, documents)), id: \.1.id
                        ) { idx, document in
                            Cell(store: store, document: document, navPath: $navPath)
                                .task {
                                    await viewModel.fetchMoreIfNeeded(currentIndex: idx)
                                }
                        }
                        .listStyle(.plain)
                    }
                    else {
                        List {
                            HStack {
                                Spacer()
                                Text("No documents")
                                Spacer()
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)
                    }
                }

                if viewModel.ready && viewModel.loading {
                    ProgressView()
                }
            }

            .onChange(of: filterState) { filter in
                Task {
                    await viewModel.refresh(filter: filter)
                    withAnimation {
                        if let document = viewModel.documents.first {
                            proxy.scrollTo(document.id, anchor: .top)
                        }
                    }
                }
            }

            .animation(.default, value: viewModel.documents)
        }
        .refreshable {
            Task { await viewModel.refresh() }
        }
        .task {
            await viewModel.load()
        }

        .onReceive(store.documentEventPublisher) { event in
            switch event {
            case .deleted(let document):
                viewModel.removed(document: document)
            case .changed(let document):
                viewModel.updated(document: document)
            case .changeReceived:
                Task { await viewModel.refresh(retain: true) }
            }
        }
    }
}
