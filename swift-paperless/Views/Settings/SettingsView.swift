//
//  SettingsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import SwiftUI
import SwiftUINavigation

// MARK: - Tag Management

extension TagView: RowViewProtocol {
    typealias Element = Tag
    init(element: Tag) {
        self.init(tag: element)
    }
}

extension TagEditView: EditViewProtocol where Element == Tag {
    init(element: Tag, onSave: @escaping (Element) throws -> Void) {
        self.init(tag: element, onSave: onSave)
    }
}

extension TagEditView: CreateViewProtocol where Element == ProtoTag {}

struct TagManager: ManagerProtocol {
    final class Model: ManagerModel {
        typealias Element = Tag
        typealias ProtoElement = ProtoTag

        private var store: DocumentStore

        init(store: DocumentStore) {
            self.store = store
        }

        func load() -> [Element] {
            return store.tags
                .map { $0.value }
                .sorted(by: { $0.name < $1.name })
        }

        func update(_ tag: Tag) async throws {
            try await store.update(tag: tag)
        }

        func create(_ tag: ProtoTag) async throws -> Tag {
            return try await store.create(tag: tag)
        }

        func delete(_ tag: Tag) async throws {
            try await store.delete(tag: tag)
        }
    }

    static var elementName: KeyPath<Tag, String> = \.name

    typealias RowView = TagView
    typealias EditView = TagEditView<Tag>
    typealias CreateView = TagEditView<ProtoTag>
}

// MARK: - Correspondent Management

extension CorrespondentEditView: EditViewProtocol where Element == Correspondent {}

extension CorrespondentEditView: CreateViewProtocol where Element == ProtoCorrespondent {}

struct CorrespondentManager: ManagerProtocol {
    static var elementName: KeyPath<Correspondent, String> = \.name

    final class Model: ManagerModel {
        typealias Element = Correspondent
        typealias ProtoElement = ProtoCorrespondent

        private var store: DocumentStore

        init(store: DocumentStore) {
            self.store = store
        }

        func load() -> [Element] {
            return store.correspondents
                .map { $0.value }
                .sorted(by: { $0.name < $1.name })
        }

        func update(_ correspondent: Correspondent) async throws {
            try await store.update(correspondent: correspondent)
        }

        func create(_ correspondent: ProtoCorrespondent) async throws -> Correspondent {
            return try await store.create(correspondent: correspondent)
        }

        func delete(_ correspondent: Correspondent) async throws {
            try await store.delete(correspondent: correspondent)
        }
    }

    typealias EditView = CorrespondentEditView<Correspondent>
    typealias CreateView = CorrespondentEditView<ProtoCorrespondent>

    struct RowView: RowViewProtocol {
        var element: Correspondent

        var body: some View {
            Text(element.name)
        }
    }
}

// MARK: - Document Type Management

extension DocumentTypeEditView: EditViewProtocol where Element == DocumentType {}

extension DocumentTypeEditView: CreateViewProtocol where Element == ProtoDocumentType {}

struct DocumentTypeManager: ManagerProtocol {
    static var elementName: KeyPath<Model.Element, String> = \.name

    final class Model: ManagerModel {
        typealias Element = DocumentType
        typealias ProtoElement = ProtoDocumentType

        private var store: DocumentStore

        init(store: DocumentStore) {
            self.store = store
        }

        func load() -> [Element] {
            return store.documentTypes
                .map { $0.value }
                .sorted(by: { $0.name < $1.name })
        }

        func update(_ dt: DocumentType) async throws {
            try await store.update(documentType: dt)
        }

        func create(_ dt: ProtoDocumentType) async throws -> DocumentType {
            return try await store.create(documentType: dt)
        }

        func delete(_ dt: DocumentType) async throws {
            try await store.delete(documentType: dt)
        }
    }

    typealias EditView = DocumentTypeEditView<DocumentType>
    typealias CreateView = DocumentTypeEditView<ProtoDocumentType>

    struct RowView: RowViewProtocol {
        var element: DocumentType

        var body: some View {
            Text(element.name)
        }
    }
}

// MARK: - Saved View Management

extension SavedViewEditView: EditViewProtocol where Element == SavedView {}

extension SavedViewEditView: CreateViewProtocol where Element == ProtoSavedView {}

struct SavedViewManager: ManagerProtocol {
    static var elementName: KeyPath<SavedView, String> = \.name

    final class Model: ManagerModel {
        typealias Element = SavedView
        typealias ProtoElement = ProtoSavedView

        private var store: DocumentStore

        init(store: DocumentStore) {
            self.store = store
        }

        func load() -> [SavedView] {
            return store.savedViews
                .map { $0.value }
                .sorted(by: { $0.name < $1.name })
        }

        func update(_ view: SavedView) async throws {
            try await store.update(savedView: view)
        }

        func create(_ view: ProtoSavedView) async throws -> SavedView {
            return try await store.create(savedView: view)
        }

        func delete(_ view: SavedView) async throws {
            try await store.delete(savedView: view)
        }
    }

    typealias EditView = SavedViewEditView<SavedView>
    typealias CreateView = SavedViewEditView<ProtoSavedView>

    struct RowView: RowViewProtocol {
        var element: SavedView

        var body: some View {
            Text(element.name)
        }
    }
}

// MARK: - Storage Paths Management

extension StoragePathEditView: EditViewProtocol where Element == StoragePath {}

extension StoragePathEditView: CreateViewProtocol where Element == ProtoStoragePath {}

struct StoragePathManager: ManagerProtocol {
    static var elementName: KeyPath<StoragePath, String> = \.name

    final class Model: ManagerModel {
        typealias Element = StoragePath
        typealias ProtoElement = ProtoStoragePath

        private var store: DocumentStore

        init(store: DocumentStore) {
            self.store = store
        }

        func load() -> [StoragePath] {
            return store.storagePaths
                .map { $0.value }
                .sorted(by: { $0.name < $1.name })
        }

        func update(_ path: StoragePath) async throws {
            try await store.update(storagePath: path)
        }

        func create(_ path: ProtoStoragePath) async throws -> StoragePath {
            return try await store.create(storagePath: path)
        }

        func delete(_ path: StoragePath) async throws {
            try await store.delete(storagePath: path)
        }
    }

    typealias EditView = StoragePathEditView<StoragePath>
    typealias CreateView = StoragePathEditView<ProtoStoragePath>

    struct RowView: RowViewProtocol {
        var element: StoragePath

        var body: some View {
            Text(element.name)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var store: DocumentStore
    @EnvironmentObject var connectionManager: ConnectionManager

    @State var extraHeaders: [ConnectionManager.HeaderValue] = []

    var body: some View {
        List {
            Section("Organization") {
                NavigationLink {
                    ManageView<TagManager>(store: store)
                        .navigationTitle("Tags")
                        .task { Task.detached { await store.fetchAllTags() }}
                } label: {
                    Label("Tags", systemImage: "tag.fill")
                }

                NavigationLink {
                    ManageView<CorrespondentManager>(store: store)
                        .navigationTitle("Correspondents")
                        .task { Task.detached { await store.fetchAllCorrespondents() }}
                } label: {
                    Label("Correspondents", systemImage: "person.fill")
                }

                NavigationLink {
                    ManageView<DocumentTypeManager>(store: store)
                        .navigationTitle("Document types")
                        .task { Task.detached { await store.fetchAllDocumentTypes() }}
                } label: {
                    Label("Document types", systemImage: "doc.fill")
                }

                NavigationLink {
                    ManageView<SavedViewManager>(store: store)
                        .navigationTitle("Saved views")
                        .task { Task.detached { await store.fetchAllDocumentTypes() }}
                } label: {
                    Label("Saved views", systemImage: "line.3.horizontal.decrease.circle.fill")
                }

                NavigationLink {
                    ManageView<StoragePathManager>(store: store)
                        .navigationTitle("Storage paths")
                        .task { Task.detached { await store.fetchAllStoragePaths() }}
                } label: {
                    Label("Storage paths", systemImage: "archivebox.fill")
                }
            }

            Section("Preferences") {
                NavigationLink {
                    PreferencesView()
                        .navigationTitle("Preferences")
                } label: {
                    Label("Preferences", systemImage: "dial.low")
                }
            }

            Section("Details") {
                NavigationLink {
                    ExtraHeadersView(headers: $extraHeaders)
                } label: {
                    Label("Extra headers", systemImage: "list.dash.header.rectangle")
                }
            }
        }

        .task {
            extraHeaders = connectionManager.extraHeaders
        }

        .onChange(of: extraHeaders) { value in
            connectionManager.extraHeaders = value
            store.set(repository: ApiRepository(connection: connectionManager.connection!))
        }

        .navigationTitle("Settings")
    }
}

struct SettingsView_Previews: PreviewProvider {
    struct Container: View {
        @StateObject var store = DocumentStore(repository: PreviewRepository())

        @StateObject var errorController = ErrorController()
        @StateObject var connectionManager = ConnectionManager()

        var body: some View {
            NavigationStack {
                SettingsView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .environmentObject(store)
            .environmentObject(connectionManager)
            .errorOverlay(errorController: errorController)
        }
    }

    static var previews: some View {
        Container()
    }
}
