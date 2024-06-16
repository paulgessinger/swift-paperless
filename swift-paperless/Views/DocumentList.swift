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
        List(documents, id: \.self) { document in
            DocumentCell(document: document, store: store)
                .redacted(reason: .placeholder)
                .padding(.horizontal)
                .padding(.vertical)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        .listStyle(.plain)
        .task {
            documents = try! await PreviewRepository().documents(filter: FilterState()).fetch(limit: 10)
        }
    }
}

struct DocumentList: View {
    var store: DocumentStore
    @Binding var navPath: NavigationPath
    @ObservedObject var filterModel: FilterModel

    @State private var documentToDelete: Document?

    @StateObject private var viewModel: DocumentListViewModel

    @EnvironmentObject private var errorController: ErrorController

    @ObservedObject private var appSettings = AppSettings.shared

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
            DocumentCell(document: document, store: store)
                .contentShape(Rectangle())

                .padding(.horizontal)
                .padding(.vertical)
                .onTapGesture {
                    navPath.append(NavigationState.detail(document: document))
                }

                .swipeActions(edge: .leading) {
                    Button {
                        Task { await viewModel.removeInboxTags(document: document) }
                    } label: {
                        Label(String(localized: .localizable(.tagsRemoveInbox)), systemImage: "tray")
                    }
                    .tint(.accentColor)
                }

                .swipeActions(edge: .trailing) {
                    Button(role: documentDeleteConfirmation ? .none : .destructive) {
                        onDeleteButtonPressed()
                    } label: {
                        Label(String(localized: .localizable(.delete)), systemImage: "trash")
                    }
                    .tint(.red)
                }

                .contextMenu {
                    Button {
                        navPath.append(NavigationState.detail(document: document))
                    } label: {
                        Label(String(localized: .localizable(.edit)), systemImage: "pencil")
                    }

                    Button {
                        Task { await viewModel.removeInboxTags(document: document) }
                    } label: {
                        Label(String(localized: .localizable(.tagsRemoveInbox)), systemImage: "tray")
                    }

                    Button(role: .destructive) {
                        onDeleteButtonPressed()
                    } label: {
                        Label(String(localized: .localizable(.delete)), systemImage: "trash")
                    }

                } preview: {
                    DocumentPreview(document: document)
                        .environmentObject(store)
                }

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
                    Label(String(localized: .localizable(.noDocuments)), systemImage: "tray.fill")
                } description: {
                    if filtering {
                        Text(.localizable(.noDocumentsDescriptionFilter))
                    }
                }
            } else {
                VStack(alignment: .center) {
                    Image(systemName: "tray.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.gray)
                        .frame(width: 75)
                    Text(.localizable(.noDocuments))
                        .font(.title2)
                        .bold()
                    if filtering {
                        Text(.localizable(.noDocumentsDescriptionFilter))
                            .font(.callout)
                    }
                }
            }
        }

        static func == (_: NoDocumentsView, _: NoDocumentsView) -> Bool {
            true
        }
    }

    private func onReceiveEvent(event: DocumentStore.Event) {
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

        case let .taskError(task: task):
            errorController.push(message: String(localized: .tasks.errorNotificationTitle),
                                 details: task.localizedResult)
        }
    }

    var body: some View {
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
                             documentDeleteConfirmation: appSettings.documentDeleteConfirmation,
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

        .onChange(of: filterModel.filterState) { _, filter in
            Task {
                if let documents = try? await viewModel.refresh(filter: filter) {
                    viewModel.replace(documents: documents)
                }
            }
        }

        // @TODO: Re-evaluate if we want an animation here
        .animation(.default, value: viewModel.documents)
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

        .onReceive(store.eventPublisher, perform: onReceiveEvent)

        // @FIXME: This somehow causes ERROR: not found in table Localizable of bundle CFBundle 0x600001730200 empty string
        .confirmationDialog(unwrapping: $documentToDelete,
                            title: { _ in String(localized: .localizable(.documentDelete)) },
                            actions: { $item in
                                let document = item
                                Button(role: .destructive) {
                                    Task {
                                        try? await store.deleteDocument(document)
                                    }
                                } label: { Text(.localizable(.documentDelete)) }
                                Button(role: .cancel) {
                                    documentToDelete = nil
                                } label: { Text(.localizable(.cancel)) }
                            },
                            message: { $item in
                                let document = item
                                Text(.localizable(.deleteDocumentName(document.title)))
                            })
    }
}
