//
//  DocumentStore.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.04.23.
//

import Combine
import Foundation
import os
import Semaphore
import SwiftUI

class DocumentStore: ObservableObject {
    // MARK: Publishers

    @Published private(set) var documents: [UInt: Document] = [:]
    @Published private(set) var correspondents: [UInt: Correspondent] = [:]
    @Published private(set) var documentTypes: [UInt: DocumentType] = [:]
    @Published private(set) var tags: [UInt: Tag] = [:]
    @Published private(set) var savedViews: [UInt: SavedView] = [:]
    @Published private(set) var storagePaths: [UInt: StoragePath] = [:]

    @Published private(set) var users: [UInt: User] = [:]
    @Published private(set) var currentUser: User?

    @Published private(set) var activeTasks: [PaperlessTask] = []

    // MARK: Members

    enum DocumentEvent {
        case deleted(document: Document)
        case changed(document: Document)
        case changeReceived(document: Document)
    }

    var documentEventPublisher =
        PassthroughSubject<DocumentEvent, Never>()

    let semaphore = AsyncSemaphore(value: 1)
    let fetchAllSemaphore = AsyncSemaphore(value: 1)

    private(set) var repository: Repository

    // MARK: Methods

    init(repository: Repository) {
        self.repository = repository
//        documentSource = NullDocumentSource()
//        documentSource = repository.documents(filter: FilterState())

        Task {
            async let _ = await fetchAll()
        }
    }

    @MainActor
    func clearDocuments() {
        documents = [:]
    }

    func set(repository: Repository) {
        self.repository = repository
    }

    @MainActor
    func updateDocument(_ document: Document) async throws {
        documentEventPublisher.send(.changed(document: document))
        documents[document.id] = try await repository.update(document: document)
        documentEventPublisher.send(.changeReceived(document: document))
    }

    @MainActor
    func deleteDocument(_ document: Document) async throws {
        try await repository.delete(document: document)
        documents.removeValue(forKey: document.id)
        documentEventPublisher.send(.deleted(document: document))
    }

    func fetchTasks() async {
        let tasks = await repository.tasks()
        let activeTasks = tasks.filter(\.isActive)
//        let inactiveTasks = tasks.filter { !$0.isActive }

        await MainActor.run {
            self.activeTasks = activeTasks
        }
    }

    func fetchAllCorrespondents() async {
        await fetchAll(elements: repository.correspondents(),
                       collection: \.correspondents)
    }

    func fetchAllDocumentTypes() async {
        await fetchAll(elements: repository.documentTypes(),
                       collection: \.documentTypes)
    }

    func fetchAllTags() async {
        await fetchAll(elements: repository.tags(),
                       collection: \.tags)
    }

    func fetchAllSavedViews() async {
        await fetchAll(elements: repository.savedViews(),
                       collection: \.savedViews)
    }

    func fetchAllStoragePaths() async {
        await fetchAll(elements: repository.storagePaths(),
                       collection: \.storagePaths)
    }

    @MainActor
    func fetchCurrentUser() async {
        if currentUser != nil {
            // We don't expect this to change
            return
        }

        do {
            currentUser = try await repository.currentUser()
        } catch {
            Logger.shared.error("Unable to get current user")
//            currentUser = User(id: UInt.max, isSuperUser: false, username: "dummy")
        }
    }

    func fetchAllUsers() async {
        await fetchAll(elements: repository.users(),
                       collection: \.users)
    }

    func fetchAll() async {
        // @TODO: This gets called concurrently during startup, maybe debounce
        Logger.shared.notice("Fetch all store request")
        await fetchAllSemaphore.wait()
        defer { fetchAllSemaphore.signal() }
        Logger.shared.notice("Fetch all store")

        let funcs = [
            fetchAllCorrespondents,
            fetchAllDocumentTypes,
            fetchAllTags,
            fetchAllSavedViews,
            fetchAllStoragePaths,
            fetchCurrentUser,
            fetchAllUsers,
        ]

        await withTaskGroup(of: Void.self) { g in
            for fn in funcs {
                g.addTask {
                    await fn()
                }
            }
        }
        Logger.shared.notice("Fetch all store complete")
    }

    @MainActor
    private func fetchAll<T>(elements: [T],
                             collection: ReferenceWritableKeyPath<DocumentStore, [UInt: T]>) async
        where T: Decodable, T: Identifiable, T.ID == UInt, T: Model
    {
        var copy = [UInt: T]()

        for element in elements {
            copy[element.id] = element
        }

        self[keyPath: collection] = copy
    }

//    @MainActor
    private func getSingleCached<T>( //        _ type: T.Type,
        get: (UInt) async -> T?, id: UInt, cache: ReferenceWritableKeyPath<DocumentStore, [UInt: T]>
    ) async -> (Bool, T)? where T: Decodable, T: Model {
        if let element = self[keyPath: cache][id] {
            return (true, element)
        }

        guard let element = await get(id) else {
            return nil
        }

        self[keyPath: cache][id] = element
        return (false, element)
    }

    func getCorrespondent(id: UInt) async -> (Bool, Correspondent)? {
        await getSingleCached(get: { await repository.correspondent(id: $0) }, id: id,
                              cache: \.correspondents)
    }

    func getDocumentType(id: UInt) async -> (Bool, DocumentType)? {
        await getSingleCached(get: { await repository.documentType(id: $0) }, id: id,
                              cache: \.documentTypes)
    }

    func document(id: UInt) async -> Document? {
        await repository.document(id: id)
    }

    func getTag(id: UInt) async -> (Bool, Tag)? {
        await getSingleCached(get: { await repository.tag(id: $0) }, id: id,
                              cache: \.tags)
    }

    func getTags(_ ids: [UInt]) async -> (Bool, [Tag]) {
        var tags: [Tag] = []
        var allCached = true
        for id in ids {
            if let (cached, tag) = await getTag(id: id) {
                tags.append(tag)
                allCached = allCached && cached
            }
        }
        return (allCached, tags)
    }

    @MainActor
    private func create<E, R>(_: R.Type, from element: E,
                              store: ReferenceWritableKeyPath<DocumentStore, [R.ID: R]>,
                              method: (E) async throws -> R) async throws -> R
        where R: Identifiable
    {
        let created = try await method(element)
        self[keyPath: store][created.id] = created
        return created
    }

    @MainActor
    private func update<E>(_ element: E,
                           store: ReferenceWritableKeyPath<DocumentStore, [E.ID: E]>,
                           method: (E) async throws -> E) async throws where E: Identifiable
    {
        self[keyPath: store][element.id] = try await method(element)
    }

    @MainActor
    private func delete<E>(_ element: E,
                           store: ReferenceWritableKeyPath<DocumentStore, [E.ID: E]>,
                           method: (E) async throws -> Void) async throws where E: Identifiable
    {
        try await method(element)
        self[keyPath: store].removeValue(forKey: element.id)
    }

    @MainActor
    func create(tag: ProtoTag) async throws -> Tag {
        try await create(Tag.self,
                         from: tag,
                         store: \.tags,
                         method: repository.create(tag:))
    }

    @MainActor
    func update(tag: Tag) async throws {
        try await update(tag, store: \.tags, method: repository.update(tag:))
    }

    @MainActor
    func delete(tag: Tag) async throws {
        try await delete(tag, store: \.tags, method: repository.delete(tag:))
    }

    @MainActor
    func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
        try await create(Correspondent.self,
                         from: correspondent,
                         store: \.correspondents,
                         method: repository.create(correspondent:))
    }

    @MainActor
    func update(correspondent: Correspondent) async throws {
        try await update(correspondent,
                         store: \.correspondents,
                         method: repository.update(correspondent:))
    }

    @MainActor
    func delete(correspondent: Correspondent) async throws {
        try await delete(correspondent,
                         store: \.correspondents,
                         method: repository.delete(correspondent:))
    }

    @MainActor
    func create(documentType: ProtoDocumentType) async throws -> DocumentType {
        try await create(DocumentType.self,
                         from: documentType,
                         store: \.documentTypes,
                         method: repository.create(documentType:))
    }

    @MainActor
    func update(documentType: DocumentType) async throws {
        try await update(documentType,
                         store: \.documentTypes,
                         method: repository.update(documentType:))
    }

    @MainActor
    func delete(documentType: DocumentType) async throws {
        try await delete(documentType,
                         store: \.documentTypes,
                         method: repository.delete(documentType:))
    }

    @MainActor
    func create(savedView: ProtoSavedView) async throws -> SavedView {
        let created = try await repository.create(savedView: savedView)
        savedViews[created.id] = created
        return created
    }

    @MainActor
    func update(savedView: SavedView) async throws {
        savedViews[savedView.id] = try await repository.update(savedView: savedView)
    }

    @MainActor
    func delete(savedView: SavedView) async throws {
        try await repository.delete(savedView: savedView)
        savedViews.removeValue(forKey: savedView.id)
    }

    @MainActor
    func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
        try await create(StoragePath.self,
                         from: storagePath,
                         store: \.storagePaths,
                         method: repository.create(storagePath:))
    }

    @MainActor
    func update(storagePath: StoragePath) async throws {
        try await update(storagePath,
                         store: \.storagePaths,
                         method: repository.update(storagePath:))
    }

    @MainActor
    func delete(storagePath: StoragePath) async throws {
        try await delete(storagePath,
                         store: \.storagePaths,
                         method: repository.delete(storagePath:))
    }
}
