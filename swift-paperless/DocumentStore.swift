//
//  DocumentStore.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.04.23.
//

import Combine
import Foundation
import Semaphore
import SwiftUI

class DocumentStore: ObservableObject {
    @Published var documents: [UInt: Document] = [:]
    @Published private(set) var correspondents: [UInt: Correspondent] = [:]
    @Published private(set) var documentTypes: [UInt: DocumentType] = [:]
    @Published private(set) var tags: [UInt: Tag] = [:]
    @Published private(set) var savedViews: [UInt: SavedView] = [:]
    @Published private(set) var storagePaths: [UInt: StoragePath] = [:]

    private var documentSource: any DocumentSource

    let semaphore = AsyncSemaphore(value: 1)
    let fetchAllSemaphore = AsyncSemaphore(value: 1)

    private(set) var repository: Repository

    func clearDocuments() {
        documents = [:]
    }

    private var tasks = Set<AnyCancellable>()

    var filterStatePublisher =
        PassthroughSubject<FilterState, Never>()

    @Published var filterState: FilterState = {
        guard let data = UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")!.object(forKey: "GlobalFilterState") as? Data else {
            print("No default")
            return FilterState()
        }
        guard let value = try? JSONDecoder().decode(FilterState.self, from: data) else {
//            print("No decode")
            return FilterState()
        }
        return value
    }() {
        didSet {
            if filterState == oldValue {
                return
            }

//            print("SET: \(filterState)")
            guard let s = try? JSONEncoder().encode(filterState) else {
//                print("NO ENCODE")
                return
            }
            UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")!.set(s, forKey: "GlobalFilterState")
        }
    }

    init(repository: Repository) {
        self.repository = repository
        documentSource = NullDocumentSource()
//        documentSource = repository.documents(filter: FilterState())

        Task {
            async let _ = await fetchAll()
        }

        $filterState
            .removeDuplicates()
            .debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                self?.filterStatePublisher.send(value)
            }
            .store(in: &tasks)
    }

    func set(repository: Repository) {
        self.repository = repository
    }

    @MainActor
    func updateDocument(_ document: Document) async throws {
        documents[document.id] = try await repository.update(document: document)
    }

    @MainActor
    func deleteDocument(_ document: Document) async throws {
        try await repository.delete(document: document)
        documents.removeValue(forKey: document.id)
    }

    func fetchDocuments(clear: Bool, pageSize: UInt = 30) async -> [Document] {
        print("fetchDocuments")
        await semaphore.wait()
        defer { semaphore.signal() }

        if clear {
            documentSource = repository.documents(filter: filterState)
        }

        let result = await documentSource.fetch(limit: pageSize)

        await MainActor.run {
            var copy = documents
            for document in result {
                copy[document.id] = document
            }
            documents = copy
        }

        return result
    }

    func hasMoreDocuments() async -> Bool {
        return await documentSource.hasMore()
    }

    func fetchAllCorrespondents() async {
        await fetchAll(elements: await repository.correspondents(),
                       collection: \.correspondents)
    }

    func fetchAllDocumentTypes() async {
        await fetchAll(elements: await repository.documentTypes(),
                       collection: \.documentTypes)
    }

    func fetchAllTags() async {
        await fetchAll(elements: await repository.tags(),
                       collection: \.tags)
    }

    func fetchAllSavedViews() async {
        await fetchAll(elements: await repository.savedViews(),
                       collection: \.savedViews)
    }

    func fetchAllStoragePaths() async {
        await fetchAll(elements: await repository.storagePaths(),
                       collection: \.storagePaths)
    }

    func fetchAll() async {
        print("Fetch all store")
        await fetchAllSemaphore.wait()
        defer { fetchAllSemaphore.signal() }

        async let c: () = fetchAllCorrespondents()
        async let d: () = fetchAllDocumentTypes()
        async let t: () = fetchAllTags()
        async let s: () = fetchAllSavedViews()
        async let p: () = fetchAllStoragePaths()
        _ = await (c, d, t, s, p)
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
    private func getSingleCached<T>(//        _ type: T.Type,
        get: (UInt) async -> T?, id: UInt, cache: ReferenceWritableKeyPath<DocumentStore, [UInt: T]>) async -> (Bool, T)? where T: Decodable, T: Model
    {
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
        return await getSingleCached(get: { await repository.correspondent(id: $0) }, id: id,
                                     cache: \.correspondents)
    }

    func getDocumentType(id: UInt) async -> (Bool, DocumentType)? {
        return await getSingleCached(get: { await repository.documentType(id: $0) }, id: id,
                                     cache: \.documentTypes)
    }

    func document(id: UInt) async -> Document? {
        return await repository.document(id: id)
    }

    func getTag(id: UInt) async -> (Bool, Tag)? {
        return await getSingleCached(get: { await repository.tag(id: $0) }, id: id,
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
    private func create<E, R>(_ returns: R.Type, from element: E,
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
        return try await create(Tag.self,
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
        return try await create(Correspondent.self,
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
        return try await create(DocumentType.self,
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
        return try await create(StoragePath.self,
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
