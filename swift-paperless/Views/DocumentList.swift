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
    private var exhausted: Bool = false

    private var initialBatchSize: UInt = 20
    private var batchSize: UInt = 100
    private var fetchMargin = 10

    init(store: DocumentStore, filterState: FilterState) {
        self.store = store
        self.filterState = filterState
        source = store.repository.documents(filter: filterState)
    }

    @MainActor
    func load() async {
        guard documents.isEmpty, !loading else { return }
        loading = true
        let batch = await source.fetch(limit: initialBatchSize)
        documents = batch
        ready = true
        loading = false
    }

    func fetchMoreIfNeeded(currentIndex: Int) async {
        if exhausted { return }
        if currentIndex >= documents.count - fetchMargin {
            guard !loading else { return }
            await MainActor.run { loading = true }
            Task.detached {
                let batch = await self.source.fetch(limit: self.batchSize)
                if batch.isEmpty {
                    self.exhausted = true
                    await MainActor.run { self.loading = false }
                    return
                }

                await MainActor.run {
                    self.documents += batch
                    self.loading = false
                }
            }
        }
    }

    @MainActor
    func refresh(filter: FilterState? = nil, retain: Bool = false) async {
        if let filter {
            filterState = filter
        }
        exhausted = false
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

    func removeInboxTags(document: Document) async {
        var document = document
        let inboxTags = store.tags.values.filter(\.isInboxTag)
        for tag in inboxTags {
            document.tags.removeAll(where: { $0 == tag.id })
        }
        try? await store.updateDocument(document)
    }
}

struct DocumentList: View {
    var store: DocumentStore
    @Binding var navPath: NavigationPath
    @Binding var filterState: FilterState

    @State private var documentToDelete: Document?

    @StateObject private var viewModel: DocumentListViewModel

    @AppStorage(SettingsKeys.documentDeleteConfirmation)
    var documentDeleteConfirmation: Bool = true

    init(store: DocumentStore, navPath: Binding<NavigationPath>, filterState: Binding<FilterState>) {
        self.store = store
        _navPath = navPath
        _filterState = filterState
        _viewModel = StateObject(wrappedValue: DocumentListViewModel(store: store, filterState: filterState.wrappedValue))
    }

    struct Cell: View {
        var store: DocumentStore
        var document: Document
        @Binding var navPath: NavigationPath
        var documentDeleteConfirmation: Bool
        @Binding var documentToDelete: Document?
        var viewModel: DocumentListViewModel

        private func onDeleteButtonPressed() async {
            if documentDeleteConfirmation {
                documentToDelete = document
            } else {
                try? await store.deleteDocument(document)
            }
        }

        var body: some View {
            ZStack {
                VStack {
                    DocumentCell(document: document)
                        .contentShape(Rectangle())

                        .padding(.horizontal)
                        .padding(.vertical)

                    Rectangle()
                        .fill(.gray)
                        .frame(height: 0.33)
                        .padding(.horizontal)
                }

                NavigationLink(value:
                    NavigationState.detail(document: document)
                ) {}
                    .frame(width: 0)
                    .opacity(0)
            }

            .swipeActions(edge: .leading) {
                Button {
                    Task { await viewModel.removeInboxTags(document: document) }
                } label: {
                    Label(String(localized: .localizable.tagsRemoveInbox), systemImage: "tray")
                }
                .tint(.accentColor)
            }

            .contextMenu {
                Button {
                    navPath.append(NavigationState.detail(document: document))
                } label: {
                    Label(String(localized: .localizable.edit), systemImage: "pencil")
                }

                Button {
                    Task { await viewModel.removeInboxTags(document: document) }
                } label: {
                    Label(String(localized: .localizable.tagsRemoveInbox), systemImage: "tray")
                }

                Button(role: .destructive) {
                    Task { await onDeleteButtonPressed() }
                } label: {
                    Label(String(localized: .localizable.delete), systemImage: "trash")
                }

            } preview: {
                DocumentPreview(document: document)
                    .environmentObject(store)
            }

            .swipeActions(edge: .trailing) {
                Button(role: documentDeleteConfirmation ? .none : .destructive) {
                    Task { await onDeleteButtonPressed() }
                } label: {
                    Label(String(localized: .localizable.delete), systemImage: "trash")
                }
                .tint(.red)
            }

            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack {
                if !viewModel.ready {
                    LoadingDocumentList()
                } else {
                    let documents = viewModel.documents
                    if !documents.isEmpty {
                        List(
                            Array(zip(documents.indices, documents)), id: \.1.id
                        ) { idx, document in
                            Cell(store: store,
                                 document: document,
                                 navPath: $navPath,
                                 documentDeleteConfirmation: documentDeleteConfirmation,
                                 documentToDelete: $documentToDelete,
                                 viewModel: viewModel)
                                .task {
                                    await viewModel.fetchMoreIfNeeded(currentIndex: idx)
                                }
                        }
                        .listStyle(.plain)
                    } else {
                        List {
                            HStack {
                                Spacer()
                                // @TODO: Make nice whimsy display
                                Text(.localizable.noDocuments)
                                Spacer()
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)
                    }
                }

                if viewModel.ready, viewModel.loading {
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
            case let .deleted(document):
                viewModel.removed(document: document)
            case let .changed(document):
                viewModel.updated(document: document)
            case .changeReceived:
                Task { await viewModel.refresh(retain: true) }
            }
        }

        // @FIXME: This somehow causes ERROR: not found in table Localizable of bundle CFBundle 0x600001730200 empty string
        .confirmationDialog(title: { _ in Text(.localizable.documentDelete) }, unwrapping: $documentToDelete) { document in
            Button(role: .destructive) {
                Task { try? await store.deleteDocument(document) }
            } label: { Text(.localizable.documentDelete) }
            Button(role: .cancel) {
                documentToDelete = nil
            } label: { Text(.localizable.cancel) }
        } message: { document in
            Text(.localizable.deleteDocumentName(document.title))
        }
    }
}
