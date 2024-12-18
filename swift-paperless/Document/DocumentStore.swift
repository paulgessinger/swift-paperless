//
//  DocumentStore.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.04.23.
//

import Combine
import DataModel
import Foundation
import os
import Semaphore
import SwiftUI

@MainActor
final class DocumentStore: ObservableObject, Sendable {
    // MARK: Publishers

    @Published private(set) var documents: [UInt: Document] = [:]
    @Published private(set) var correspondents: [UInt: Correspondent] = [:]
    @Published private(set) var documentTypes: [UInt: DocumentType] = [:]
    @Published private(set) var tags: [UInt: Tag] = [:]
    @Published private(set) var savedViews: [UInt: SavedView] = [:]
    @Published private(set) var storagePaths: [UInt: StoragePath] = [:]

    @Published private(set) var users: [UInt: User] = [:]
    @Published private(set) var groups: [UInt: UserGroup] = [:]
    @Published private(set) var currentUser: User?

    @Published private(set) var tasks: [PaperlessTask] = []

    var activeTasks: [PaperlessTask] {
        tasks.filter(\.isActive)
    }

    // MARK: Members

    enum Event {
        case deleted(document: Document)
        case changed(document: Document)
        case changeReceived(document: Document)

        case repositoryWillChange
        case repositoryChanged
        case taskError(task: PaperlessTask)
    }

    var eventPublisher =
        PassthroughSubject<Event, Never>()

    let semaphore = AsyncSemaphore(value: 1)
    let fetchAllSemaphore = AsyncSemaphore(value: 1)

    private(set) var repository: any Repository

    private var taskUpdateTask: Task<Void, Never>?

    // MARK: Methods

    init(repository: some Repository) {
        self.repository = repository
    }

    deinit {
        taskUpdateTask?.cancel()
    }

    @Sendable
    private func taskPoller() async {
        Logger.shared.debug("Task poller initialize")
        repeat {
            guard !Task.isCancelled else { break }
            Logger.shared.debug("Polling tasks")

            let currentActiveTasks = Set(tasks.filter(\.isActive).map(\.id))
            Logger.shared.debug("Current active: \(currentActiveTasks)")
            await fetchTasks()
            let newErrors: [PaperlessTask] = tasks.filter { $0.status == .FAILURE && currentActiveTasks.contains($0.id) }
            Logger.shared.debug("New errors: \(newErrors)")

            if !newErrors.isEmpty {
                Task {
                    // don't send the errors all at once if there's multiple
                    for task in newErrors {
                        eventPublisher.send(.taskError(task: task))
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
            }

            let duration: Duration = .seconds(activeTasks.isEmpty ? 60 : 2.5)
            Logger.shared.debug("Task poller sleeping for \(duration)")
            try? await Task.sleep(for: duration)
        } while !Task.isCancelled
        Logger.shared.debug("Task poller terminating")
    }

    func startTaskPolling() {
        taskUpdateTask?.cancel()
        taskUpdateTask = Task(operation: taskPoller)
    }

    func clearDocuments() {
        documents = [:]
    }

    func clear() {
        documents = [:]
        correspondents = [:]
        documentTypes = [:]
        tags = [:]
        savedViews = [:]
        storagePaths = [:]
        users = [:]
        groups = [:]
        currentUser = nil
        tasks = []
    }

    func set(repository: some Repository) {
        self.repository = repository
        eventPublisher.send(.repositoryChanged)
        clear()
    }

    func updateDocument(_ document: Document) async throws -> Document {
        eventPublisher.send(.changed(document: document))
        let document = try await repository.update(document: document)
        documents[document.id] = document
        eventPublisher.send(.changeReceived(document: document))
        return document
    }

    func deleteDocument(_ document: Document) async throws {
        try await repository.delete(document: document)
        documents.removeValue(forKey: document.id)
        eventPublisher.send(.deleted(document: document))
    }

    func deleteNote(from document: Document, id: UInt) async throws {
        eventPublisher.send(.changed(document: document))
        let notes = try await repository.deleteNote(id: id, documentId: document.id)

        var document = document
        document.notes = notes

        documents[document.id] = document
        eventPublisher.send(.changeReceived(document: document))
    }

    func addNote(to document: Document, note: ProtoDocument.Note) async throws {
        eventPublisher.send(.changed(document: document))

        let notes = try await repository.createNote(documentId: document.id, note: note)

        var document = document
        document.notes = notes

        documents[document.id] = document
        eventPublisher.send(.changeReceived(document: document))
    }

    func fetchTasks() async {
        guard let tasks = try? await repository.tasks() else {
            return
        }
        self.tasks = tasks
    }

    func acknowledge(tasks ids: [UInt]) async throws {
        try await repository.acknowledge(tasks: ids)
        await fetchTasks()
    }

    func fetchAllCorrespondents() async throws {
        try await fetchAll(elements: repository.correspondents(),
                           collection: \.correspondents)
    }

    func fetchAllDocumentTypes() async throws {
        try await fetchAll(elements: repository.documentTypes(),
                           collection: \.documentTypes)
    }

    func fetchAllTags() async throws {
        try await fetchAll(elements: repository.tags(),
                           collection: \.tags)
    }

    func fetchAllSavedViews() async throws {
        try await fetchAll(elements: repository.savedViews(),
                           collection: \.savedViews)
    }

    func fetchAllStoragePaths() async throws {
        try await fetchAll(elements: repository.storagePaths(),
                           collection: \.storagePaths)
    }

    func fetchCurrentUser() async throws {
        if currentUser != nil {
            // We don't expect this to change
            return
        }

        do {
            let user = try await repository.currentUser()
            await MainActor.run {
                currentUser = user
            }
        } catch {
            Logger.shared.error("Unable to get current user: \(error)")
        }
    }

    func fetchAllUsers() async throws {
        try await fetchAll(elements: repository.users(),
                           collection: \.users)
    }

    func fetchAllGroups() async throws {
        try await fetchAll(elements: repository.groups(),
                           collection: \.groups)
    }

    func fetchAll() async throws {
        // @TODO: This gets called concurrently during startup, maybe debounce
        Logger.shared.notice("Fetch all store request")
        await fetchAllSemaphore.wait()
        defer { fetchAllSemaphore.signal() }
        Logger.shared.notice("Fetch all store")

        async let correspondents: Void = fetchAllCorrespondents()
        async let documentTypes: Void = fetchAllDocumentTypes()
        async let tags: Void = fetchAllTags()
        async let savedViews: Void = fetchAllSavedViews()
        async let storagePaths: Void = fetchAllStoragePaths()
        async let currentUser: Void = fetchCurrentUser()
        async let users: Void = fetchAllUsers()
        async let groups: Void = fetchAllGroups()

        _ = try await (correspondents, documentTypes, tags, savedViews, storagePaths, currentUser, users, groups)

        Logger.shared.notice("Fetch all store complete")
    }

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

    private func getSingleCached<T: Sendable>(
        get: (UInt) async throws -> T?, id: UInt, cache: ReferenceWritableKeyPath<DocumentStore, [UInt: T]>
    ) async throws -> (Bool, T)? where T: Decodable, T: Model {
        if let element = self[keyPath: cache][id] {
            return (true, element)
        }

        guard let element = try await get(id) else {
            return nil
        }

        self[keyPath: cache][id] = element
        return (false, element)
    }

    func getCorrespondent(id: UInt) async throws -> (Bool, Correspondent)? {
        try await getSingleCached(get: { try await repository.correspondent(id: $0) }, id: id,
                                  cache: \.correspondents)
    }

    func getDocumentType(id: UInt) async throws -> (Bool, DocumentType)? {
        try await getSingleCached(get: { try await repository.documentType(id: $0) }, id: id,
                                  cache: \.documentTypes)
    }

    func document(id: UInt) async throws -> Document? {
        try await repository.document(id: id)
    }

    func getTag(id: UInt) async throws -> (Bool, Tag)? {
        try await getSingleCached(get: { try await repository.tag(id: $0) }, id: id,
                                  cache: \.tags)
    }

    func getTags(_ ids: [UInt]) async throws -> (Bool, [Tag]) {
        var tags: [Tag] = []
        var allCached = true
        for id in ids {
            if let (cached, tag) = try await getTag(id: id) {
                tags.append(tag)
                allCached = allCached && cached
            }
        }
        return (allCached, tags)
    }

    private func create<E: Sendable, R: Sendable>(_: R.Type, from element: E,
                                                  store: ReferenceWritableKeyPath<DocumentStore, [R.ID: R]>,
                                                  method: (E) async throws -> R) async throws -> R
        where R: Identifiable
    {
        let created = try await method(element)
        self[keyPath: store][created.id] = created
        return created
    }

    private func update<E: Sendable>(_ element: E,
                                     store: ReferenceWritableKeyPath<DocumentStore, [E.ID: E]>,
                                     method: (E) async throws -> E) async throws where E: Identifiable
    {
        self[keyPath: store][element.id] = try await method(element)
    }

    private func delete<E: Sendable>(_ element: E,
                                     store: ReferenceWritableKeyPath<DocumentStore, [E.ID: E]>,
                                     method: (E) async throws -> Void) async throws where E: Identifiable
    {
        try await method(element)
        self[keyPath: store].removeValue(forKey: element.id)
    }

    func create(tag: ProtoTag) async throws -> Tag {
        try await create(Tag.self,
                         from: tag,
                         store: \.tags,
                         method: repository.create(tag:))
    }

    func update(tag: Tag) async throws {
        try await update(tag, store: \.tags, method: repository.update(tag:))
    }

    func delete(tag: Tag) async throws {
        try await delete(tag, store: \.tags, method: repository.delete(tag:))
    }

    func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
        try await create(Correspondent.self,
                         from: correspondent,
                         store: \.correspondents,
                         method: repository.create(correspondent:))
    }

    func update(correspondent: Correspondent) async throws {
        try await update(correspondent,
                         store: \.correspondents,
                         method: repository.update(correspondent:))
    }

    func delete(correspondent: Correspondent) async throws {
        try await delete(correspondent,
                         store: \.correspondents,
                         method: repository.delete(correspondent:))
    }

    func create(documentType: ProtoDocumentType) async throws -> DocumentType {
        try await create(DocumentType.self,
                         from: documentType,
                         store: \.documentTypes,
                         method: repository.create(documentType:))
    }

    func update(documentType: DocumentType) async throws {
        try await update(documentType,
                         store: \.documentTypes,
                         method: repository.update(documentType:))
    }

    func delete(documentType: DocumentType) async throws {
        try await delete(documentType,
                         store: \.documentTypes,
                         method: repository.delete(documentType:))
    }

    func create(savedView: ProtoSavedView) async throws -> SavedView {
        let created = try await repository.create(savedView: savedView)
        savedViews[created.id] = created
        return created
    }

    func create(document: ProtoDocument, file: URL) async throws {
        try await repository.create(document: document, file: file)
        startTaskPolling()
    }

    func update(savedView: SavedView) async throws {
        savedViews[savedView.id] = try await repository.update(savedView: savedView)
    }

    func delete(savedView: SavedView) async throws {
        try await repository.delete(savedView: savedView)
        savedViews.removeValue(forKey: savedView.id)
    }

    func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
        try await create(StoragePath.self,
                         from: storagePath,
                         store: \.storagePaths,
                         method: repository.create(storagePath:))
    }

    func update(storagePath: StoragePath) async throws {
        try await update(storagePath,
                         store: \.storagePaths,
                         method: repository.update(storagePath:))
    }

    func delete(storagePath: StoragePath) async throws {
        try await delete(storagePath,
                         store: \.storagePaths,
                         method: repository.delete(storagePath:))
    }
}
