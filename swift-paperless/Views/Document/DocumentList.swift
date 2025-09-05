//
//  DocumentList.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.07.23.
//

import Combine
import DataModel
import Foundation
import Networking
import os
import SwiftUI

struct LoadingDocumentList: View {
    @State private var documents: [Document] = []
    @StateObject private var store = DocumentStore(repository: PreviewRepository())

    var body: some View {
        List {
            Section {
                ForEach(documents, id: \.self) { document in
                    DocumentCell(document: document, store: store)
                        .redacted(reason: .placeholder)
                        .padding(.horizontal)
                        .padding(.vertical)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 15 }
                }
            }
            .listSectionSeparator(.hidden)
        }
        .listStyle(.plain)
        .task {
            documents = try! await PreviewRepository().documents(filter: .default).fetch(limit: 10)
        }
    }
}

struct DocumentList: View {
    var store: DocumentStore
    @Binding var navPath: NavigationPath
    @ObservedObject var filterModel: FilterModel

    @State private var documentToDelete: Document?

    @State private var viewModel: DocumentListViewModel

    @EnvironmentObject private var errorController: ErrorController

    @ObservedObject private var appSettings = AppSettings.shared

    init(store: DocumentStore, navPath: Binding<NavigationPath>, filterModel: FilterModel, errorController: ErrorController) {
        self.store = store
        _navPath = navPath
        self.filterModel = filterModel
        _viewModel = State(initialValue: DocumentListViewModel(store: store,
                                                               filterState: filterModel.filterState,
                                                               errorController: errorController))
    }

    struct Cell: View {
        var store: DocumentStore
        var document: Document
        @Binding var navPath: NavigationPath
        var documentDeleteConfirmation: Bool
        @Binding var documentToDelete: Document?
        var viewModel: DocumentListViewModel

        @EnvironmentObject private var errorController: ErrorController

        private func onDeleteButtonPressed() {
            if documentDeleteConfirmation {
                documentToDelete = document
            } else {
                Task { [store = self.store, document = self.document] in
                    do {
                        try await store.deleteDocument(document)
                    } catch {
                        Logger.shared.error("Error deleting document: \(error)")
                        errorController.push(error: error)
                    }
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
                    if store.permissions.test(.delete, for: .document) {
                        Button(role: documentDeleteConfirmation ? .none : .destructive) {
                            onDeleteButtonPressed()
                        } label: {
                            Label(String(localized: .localizable(.delete)), systemImage: "trash")
                        }
                        .tint(.red)
                    }
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
            filterModel.ready = false
            viewModel.ready = false
        case .repositoryChanged:
            Task {
                await viewModel.reload()
            }
            Task {
                filterModel.filterState.clear()
                try? await Task.sleep(for: .seconds(0.5))
                filterModel.ready = true
            }
        case let .taskError(task: task):
            errorController.push(message: String(localized: .tasks(.errorNotificationTitle)),
                                 details: task.localizedResult)
        }
    }

    func refresh() async {
        do {
            let documents = try await viewModel.refresh()
            withAnimation {
                viewModel.replace(documents: documents)
            }
        } catch {
            Logger.shared.error("Error refreshing documents: \(error)")
        }
    }

    var body: some View {
        VStack {
            if !viewModel.ready {
                LoadingDocumentList()
            } else if viewModel.noPermissions {
                NoPermissionsView(for: Document.self)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .refreshable {
                        await Task {
                            await refresh()
                        }.value
                    }
            } else {
                let documents = viewModel.documents
                if !documents.isEmpty {
                    List {
                        Section {
                            ForEach(Array(zip(documents.indices, documents)), id: \.1.id) { idx, document in
                                Cell(store: store,
                                     document: document,
                                     navPath: $navPath,
                                     documentDeleteConfirmation: appSettings.documentDeleteConfirmation,
                                     documentToDelete: $documentToDelete,
                                     viewModel: viewModel)

                                    .alignmentGuide(.listRowSeparatorLeading) { _ in 15 }

                                    .task {
                                        await viewModel.fetchMoreIfNeeded(currentIndex: idx)
                                    }
                            }
                        }
                        .listSectionSeparator(.hidden)
                    }
                    .listStyle(.plain)
                } else {
                    NoDocumentsView(filtering: filterModel.filterState.filtering)
                        .equatable()
                        .refreshable {
                            await Task {
                                await refresh()
                            }.value
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .animation(.default, value: viewModel.ready)
        .animation(.default, value: viewModel.noPermissions)

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
            await Task {
                await refresh()
            }.value
        }

        .task {
            await viewModel.load()
            viewModel.ready = true
        }

        .onReceive(store.eventPublisher, perform: onReceiveEvent)

        // @FIXME: This somehow causes ERROR: not found in table Localizable of bundle CFBundle 0x600001730200 empty string
        .confirmationDialog(unwrapping: $documentToDelete,
                            title: { _ in String(localized: .localizable(.documentDelete)) },
                            actions: { $item in
                                let document = item
                                Button(role: .destructive) {
                                    Task {
                                        do {
                                            try await store.deleteDocument(document)
                                        } catch {
                                            Logger.shared.error("Error deleting document: \(error)")
                                            errorController.push(error: error)
                                        }
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

private struct NoDocumentsView: View, Equatable {
    var filtering: Bool

    // Workaround to make SwiftUI call the == func to skip rerendering this view
    @State private var dummy = 5

    var body: some View {
        ScrollView(.vertical) {
            ContentUnavailableView {
                Label(String(localized: .localizable(.noDocuments)), systemImage: "tray.fill")
            } description: {
                if filtering {
                    Text(.localizable(.noDocumentsDescriptionFilter))
                }
            }

            .padding(.top, 40)
        }
    }

    nonisolated
    static func == (_: NoDocumentsView, _: NoDocumentsView) -> Bool {
        true
    }
}

private struct NoPermissionsViewDocument: View {
    var body: some View {
        ScrollView(.vertical) {
            ContentUnavailableView {
                Label(String(localized: .localizable(.requestErrorForbidden)), systemImage: "lock.fill")
            } description: {
                Text(.localizable(.documentsNoPermissionsDescription))
            }
            .padding(.top, 40)
        }
    }
}

// - MARK: Previews

#Preview("NoDocumentsView") {
    NoDocumentsView(filtering: true)
}
