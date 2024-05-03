//
//  DocumentList.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.07.23.
//

import Combine
import Foundation
import os
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
            documents = try! await PreviewRepository().documents(filter: FilterState()).fetch(limit: 10)
        }
    }
}

@MainActor
class DocumentListViewModel: ObservableObject {
    private var store: DocumentStore
    private var filterState: FilterState
    private var errorController: ErrorController

    @Published var documents: [Document] = []
    @Published var loading = false
    @Published var ready = false

    private var source: DocumentSource?
    private var exhausted: Bool = false

    private var initialBatchSize: UInt = 20
    private var batchSize: UInt = 100
    private var fetchMargin = 10

    init(store: DocumentStore, filterState: FilterState, errorController: ErrorController) {
        self.store = store
        self.filterState = filterState
        self.errorController = errorController
    }

    func reload() async {
        do {
            source = try await store.repository.documents(filter: filterState)
            documents = []
            await load()
        } catch {
            Logger.shared.error("Error getting reloaded document source: \(error)")
            errorController.push(error: error)
        }
    }

    func load() async {
        guard documents.isEmpty, !loading else { return }
        loading = true
        do {
            if source == nil {
                source = try await store.repository.documents(filter: filterState)
            }
            let batch = try await source!.fetch(limit: initialBatchSize)
            documents = batch
            ready = true
            loading = false
        } catch {
            Logger.shared.error("DocumentList failed to load documents: \(error)")
            errorController.push(error: error)
        }
    }

    func fetchMoreIfNeeded(currentIndex: Int) async {
        if exhausted { return }
        if currentIndex >= documents.count - fetchMargin {
            guard !loading else { return }
            await MainActor.run { loading = true }
            Task.detached {
                do {
                    guard let source = await self.source else {
                        return
                    }
                    let batch = try await source.fetch(limit: self.batchSize)
                    if batch.isEmpty {
                        await MainActor.run {
                            self.exhausted = true
                            self.loading = false
                        }
                        return
                    }

                    await MainActor.run {
                        self.documents += batch
                        self.loading = false
                    }
                } catch {
                    Logger.shared.error("DocumentList failed to load more if needed: \(error)")
                    await self.errorController.push(error: error)
                }
            }
        }
    }

    func refresh(filter: FilterState? = nil, retain: Bool = false) async throws -> [Document] {
        if let filter {
            filterState = filter
        }
        exhausted = false
        do {
            source = try await store.repository.documents(filter: filterState)
            guard let source else {
                return []
            }
            let batch = try await source.fetch(limit: retain ? UInt(documents.count) : initialBatchSize)
            return batch
        } catch {
            Logger.shared.error("DocumentList failed to refresh: \(error)")
            errorController.push(error: error)
            throw error
        }
    }

    func replace(documents: [Document]) {
        self.documents = documents
    }

    func removed(document: Document) {
        documents.removeAll(where: { $0.id == document.id })
    }

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
    @ObservedObject var filterModel: FilterModel

    @State private var documentToDelete: Document?

    @StateObject private var viewModel: DocumentListViewModel

    @AppStorage(SettingsKeys.documentDeleteConfirmation)
    var documentDeleteConfirmation: Bool = true

    init(store: DocumentStore, navPath: Binding<NavigationPath>, filterModel: FilterModel, errorController: ErrorController) {
        self.store = store
        _navPath = navPath
        self.filterModel = filterModel
        _viewModel = StateObject(wrappedValue: DocumentListViewModel(store: store, filterState: filterModel.filterState, errorController: errorController))
    }

    struct Cell: View {
        var store: DocumentStore
        var document: Document
        @Binding var navPath: NavigationPath
        var documentDeleteConfirmation: Bool
        @Binding var documentToDelete: Document?
        var viewModel: DocumentListViewModel

        private func onDeleteButtonPressed() {
            if documentDeleteConfirmation {
                documentToDelete = document
            } else {
                Task { [store = self.store, document = self.document] in
                    try? await store.deleteDocument(document)
                }
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
                    onDeleteButtonPressed()
                } label: {
                    Label(String(localized: .localizable.delete), systemImage: "trash")
                }

            } preview: {
                DocumentPreview(document: document)
                    .environmentObject(store)
            }

            .swipeActions(edge: .trailing) {
                Button(role: documentDeleteConfirmation ? .none : .destructive) {
                    onDeleteButtonPressed()
                } label: {
                    Label(String(localized: .localizable.delete), systemImage: "trash")
                }
                .tint(.red)
            }

            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    private struct NoDocumentsView: View, Equatable {
        var filtering: Bool

        // Workaround to make SwiftUI call the == func to skip rerendering this view
        @State private var dummy = 5

        var body: some View {
            if #available(iOS 17.0, macOS 14.0, *) {
                ContentUnavailableView {
                    Label(String(localized: .localizable.noDocuments), systemImage: "tray.fill")
                } description: {
                    if filtering {
                        Text(.localizable.noDocumentsDescriptionFilter)
                    }
                }
            } else {
                VStack(alignment: .center) {
                    Image(systemName: "tray.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.gray)
                        .frame(width: 75)
                    Text(.localizable.noDocuments)
                        .font(.title2)
                        .bold()
                    if filtering {
                        Text(.localizable.noDocumentsDescriptionFilter)
                            .font(.callout)
                    }
                }
            }
        }

        static func == (_: NoDocumentsView, _: NoDocumentsView) -> Bool {
            true
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
                        NoDocumentsView(filtering: filterModel.filterState.filtering)
                            .equatable()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
            }

            .onChange(of: filterModel.filterState) { filter in
                Task {
                    if let documents = try? await viewModel.refresh(filter: filter) {
                        viewModel.replace(documents: documents)
                        if let document = viewModel.documents.first {
                            proxy.scrollTo(document.id, anchor: .top)
                        }
                    }
                }
            }

            // @TODO: Re-evaluate if we want an animation here
//            .animation(.default, value: viewModel.documents)
        }
        .refreshable {
            Task {
                if let documents = try? await viewModel.refresh() {
                    withAnimation {
                        viewModel.replace(documents: documents)
                    }
                }
            }
        }
        .task {
            await viewModel.load()
        }

        .onReceive(store.documentEventPublisher) { event in
            switch event {
            case let .deleted(document):
                withAnimation {
                    viewModel.removed(document: document)
                }
            case let .changed(document):
                viewModel.updated(document: document)
            case .changeReceived:
                Task {
                    if let documents = try? await viewModel.refresh(retain: true) {
                        withAnimation {
                            viewModel.replace(documents: documents)
                        }
                    }
                }
            case .repositoryWillChange:
                withAnimation {
                    viewModel.ready = false
                    filterModel.ready = false
                }
            case .repositoryChanged:
                Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    await viewModel.reload()
                }
                Task {
                    filterModel.filterState.clear()
                    try? await Task.sleep(for: .seconds(0.5))
                    filterModel.ready = true
                }
            }
        }

        // @FIXME: This somehow causes ERROR: not found in table Localizable of bundle CFBundle 0x600001730200 empty string
        .confirmationDialog(unwrapping: $documentToDelete,
                            title: { _ in String(localized: .localizable.documentDelete) },
                            actions: { $item in
                                let document = item
                                Button(role: .destructive) {
                                    Task {
                                        try? await store.deleteDocument(document)
                                    }
                                } label: { Text(.localizable.documentDelete) }
                                Button(role: .cancel) {
                                    documentToDelete = nil
                                } label: { Text(.localizable.cancel) }
                            },
                            message: { $item in
                                let document = item
                                Text(.localizable.deleteDocumentName(document.title))
                            })
    }
}
