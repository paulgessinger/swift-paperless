import DataModel
import Foundation
import os
import SwiftUI

public actor TransientRepository {
    private var documents: [UInt: Document]
    private var tags: [UInt: Tag]
    private var documentTypes: [UInt: DocumentType]
    private var correspondents: [UInt: Correspondent]
    private var storagePaths: [UInt: StoragePath]
    private var tasks: [PaperlessTask]
    private var users: [User]
    private var groups: [UserGroup]
    private var savedViews: [UInt: SavedView]

    private var notesByDocument: [UInt: [Document.Note]]

    private var customFields: [UInt: CustomField]

    private var permissions: UserPermissions = .full

    private var nextId: UInt = 1
    private var currentLoggedInUser: User?

    public init() {
        documents = [:]
        tags = [:]
        documentTypes = [:]
        correspondents = [:]
        storagePaths = [:]
        tasks = []
        users = []
        groups = []
        savedViews = [:]
        customFields = [:]
        notesByDocument = [:]
    }

    private func generateId() -> UInt {
        defer { nextId += 1 }
        return nextId
    }

    // MARK: - User Management

    /// Adds a user to the repository's user list
    public func addUser(_ user: User) {
        users.append(user)
    }

    /// Adds a group to the repository's group list
    public func addGroup(_ group: UserGroup) {
        groups.append(group)
    }

    /// Logs in a user by ID. The user must exist in the repository's user list.
    /// - Parameter userId: The ID of the user to log in
    /// - Throws: RepositoryError.userNotFound if the user doesn't exist
    public func login(userId: UInt) throws {
        guard let user = users.first(where: { $0.id == userId }) else {
            throw RepositoryError.userNotFound
        }
        currentLoggedInUser = user
    }

    /// Logs in a user by username. The user must exist in the repository's user list.
    /// - Parameter username: The username of the user to log in
    /// - Throws: RepositoryError.userNotFound if the user doesn't exist
    public func login(username: String) throws {
        guard let user = users.first(where: { $0.username == username }) else {
            throw RepositoryError.userNotFound
        }
        currentLoggedInUser = user
    }

    /// Logs out the current user
    public func logout() {
        currentLoggedInUser = nil
    }

    public func set(permissions: UserPermissions) {
        self.permissions = permissions
    }

    public func set(
        permissionTo op: UserPermissions.Operation, for resource: UserPermissions.Resource,
        to value: Bool
    ) {
        permissions.set(op, to: value, for: resource)
    }
}

// MARK: - Repository Conformance

extension TransientRepository: Repository {
    // MARK: - Documents

    public func update(document: Document) async throws -> Document {
        documents[document.id] = document
        return document
    }

    public func document(id: UInt) async throws -> Document? {
        documents[id]
    }

    public func document(asn: UInt) async throws -> Document? {
        documents.first(where: { $0.value.asn == asn })?.value
    }

    public func documents(filter: FilterState) throws -> any DocumentSource {
        let filteredDocs = documents.values.filter { doc in
            if !filter.searchText.isEmpty {
                return doc.title.localizedCaseInsensitiveContains(filter.searchText)
            }
            return true
        }.sorted { $0.id < $1.id }
        return TransientDocumentSource(sequence: filteredDocs)
    }

    public func allDocuments() -> [Document] {
        documents.values.sorted { $0.id < $1.id }
    }

    public func nextAsn() async throws -> UInt {
        (documents.compactMap(\.value.asn).max() ?? 0) + 1
    }

    public func delete(document: Document) async throws {
        documents.removeValue(forKey: document.id)
    }

    public func create(document: ProtoDocument, file _: URL, filename _: String) async throws {
        let id = generateId()
        let newDoc = Document(
            id: id,
            title: document.title,
            asn: document.asn,
            documentType: document.documentType,
            correspondent: document.correspondent,
            created: document.created,
            tags: document.tags,
            added: .now,
            modified: .now,
            storagePath: document.storagePath
        )
        documents[id] = newDoc
    }

    // MARK: - Tags

    public func tag(id: UInt) async throws -> Tag? {
        tags[id]
    }

    public func tags() async throws -> [Tag] {
        tags.map(\.value)
    }

    public func create(tag: ProtoTag) async throws -> Tag {
        let id = generateId()
        let newTag = Tag(
            id: id,
            isInboxTag: tag.isInboxTag,
            name: tag.name,
            slug: tag.name.lowercased(),
            color: tag.color,
            match: tag.match,
            matchingAlgorithm: tag.matchingAlgorithm,
            isInsensitive: tag.isInsensitive
        )
        tags[id] = newTag
        return newTag
    }

    public func update(tag: Tag) async throws -> Tag {
        tags[tag.id] = tag
        return tag
    }

    public func delete(tag: Tag) async throws {
        tags.removeValue(forKey: tag.id)
    }

    // MARK: - Correspondents

    public func correspondent(id: UInt) async throws -> Correspondent? {
        correspondents[id]
    }

    public func correspondents() async throws -> [Correspondent] {
        correspondents.map(\.value)
    }

    public func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
        let id = generateId()
        let newCorrespondent = Correspondent(
            id: id,
            name: correspondent.name,
            slug: correspondent.name.lowercased(),
            matchingAlgorithm: correspondent.matchingAlgorithm,
            match: correspondent.match,
            isInsensitive: correspondent.isInsensitive
        )
        correspondents[id] = newCorrespondent
        return newCorrespondent
    }

    public func update(correspondent: Correspondent) async throws -> Correspondent {
        correspondents[correspondent.id] = correspondent
        return correspondent
    }

    public func delete(correspondent: Correspondent) async throws {
        correspondents.removeValue(forKey: correspondent.id)
    }

    // MARK: - Document Types

    public func documentType(id: UInt) async throws -> DocumentType? {
        documentTypes[id]
    }

    public func create(documentType: ProtoDocumentType) async throws -> DocumentType {
        let id = generateId()
        let newDocumentType = DocumentType(
            id: id,
            name: documentType.name,
            slug: documentType.name.lowercased(),
            match: documentType.match,
            matchingAlgorithm: documentType.matchingAlgorithm,
            isInsensitive: documentType.isInsensitive
        )
        documentTypes[id] = newDocumentType
        return newDocumentType
    }

    public func update(documentType: DocumentType) async throws -> DocumentType {
        documentTypes[documentType.id] = documentType
        return documentType
    }

    public func delete(documentType: DocumentType) async throws {
        documentTypes.removeValue(forKey: documentType.id)
    }

    public func documentTypes() async throws -> [DocumentType] {
        documentTypes.map(\.value)
    }

    // MARK: - Storage Paths

    public func storagePaths() async throws -> [StoragePath] {
        storagePaths.map(\.value)
    }

    public func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
        let id = generateId()
        let newStoragePath = StoragePath(
            id: id,
            name: storagePath.name,
            path: storagePath.path,
            slug: storagePath.name.lowercased(),
            matchingAlgorithm: storagePath.matchingAlgorithm,
            match: storagePath.match,
            isInsensitive: storagePath.isInsensitive
        )
        storagePaths[id] = newStoragePath
        return newStoragePath
    }

    public func update(storagePath: StoragePath) async throws -> StoragePath {
        storagePaths[storagePath.id] = storagePath
        return storagePath
    }

    public func delete(storagePath: StoragePath) async throws {
        storagePaths.removeValue(forKey: storagePath.id)
    }

    // MARK: - Saved Views

    public func savedViews() async throws -> [SavedView] {
        savedViews.map(\.value)
    }

    public func create(savedView: ProtoSavedView) async throws -> SavedView {
        let id = generateId()
        let newSavedView = SavedView(
            id: id,
            name: savedView.name,
            showOnDashboard: savedView.showOnDashboard,
            showInSidebar: savedView.showInSidebar,
            sortField: savedView.sortField,
            sortOrder: savedView.sortOrder,
            filterRules: savedView.filterRules
        )
        savedViews[id] = newSavedView
        return newSavedView
    }

    public func update(savedView: SavedView) async throws -> SavedView {
        savedViews[savedView.id] = savedView
        return savedView
    }

    public func delete(savedView: SavedView) async throws {
        savedViews.removeValue(forKey: savedView.id)
    }

    // MARK: - Users and Groups

    public func currentUser() async throws -> User {
        if let currentLoggedInUser {
            return currentLoggedInUser
        }
        throw RepositoryError.noUserLoggedIn
    }

    public func users() async throws -> [User] {
        users
    }

    public func groups() async throws -> [UserGroup] {
        groups
    }

    // MARK: - Tasks

    public func tasks() async throws -> [PaperlessTask] {
        tasks
    }

    public func task(id: UInt) async throws -> PaperlessTask? {
        tasks.first { $0.id == id }
    }

    public func acknowledge(tasks ids: [UInt]) async throws {
        for id in ids {
            if let index = tasks.firstIndex(where: { $0.id == id }) {
                var task = tasks[index]
                task.acknowledged = true
                tasks[index] = task
            }
        }
    }

    // MARK: - Custom fields

    public func customFields() async throws -> [CustomField] {
        customFields.map(\.value)
    }

    // This is not part of the `Repository` protocol, but it's useful for testing
    public func add(customField: CustomField) async throws -> CustomField {
        customFields[customField.id] = customField
        return customField
    }

    // MARK: - Document Operations

    public func metadata(documentId _: UInt) async throws -> Metadata {
        Metadata(
            originalChecksum: "transient-checksum",
            originalSize: 0,
            originalMimeType: "application/pdf",
            mediaFilename: "transient/document.pdf",
            hasArchiveVersion: false,
            originalMetadata: [],
            archiveChecksum: nil,
            archiveMediaFilename: nil,
            originalFilename: "document.pdf",
            archiveSize: nil,
            archiveMetadata: [],
            lang: "en"
        )
    }

    public func notes(documentId: UInt) async throws -> [Document.Note] {
        notesByDocument[documentId, default: []]
    }

    public func createNote(documentId: UInt, note: ProtoDocument.Note) async throws -> [Document
        .Note]
    {
        guard let document = documents[documentId] else {
            throw RepositoryError.documentNotFound
        }

        // Get higest note id and increment it
        let values = notesByDocument.flatMap { $0.value.map(\.id) }
        let nextId = values.max() ?? 0 + 1
        let newNote = Document.Note(id: nextId, note: note.note, created: .now)
        notesByDocument[documentId, default: []].append(newNote)
        documents[documentId] = document
        return notesByDocument[documentId, default: []]
    }

    public func deleteNote(id: UInt, documentId: UInt) async throws -> [Document.Note] {
        guard documents[documentId] != nil else {
            throw RepositoryError.documentNotFound
        }

        guard var notes = notesByDocument[documentId] else {
            return []
        }

        notes = notes.filter { $0.id != id }

        notesByDocument[documentId] = notes

        return notes
    }

    public func download(documentID _: UInt, progress: (@Sendable (Double) -> Void)? = nil)
        async throws -> URL?
    {
        // Simulate download progress
        for i in 1 ... 10 {
            try await Task.sleep(for: .seconds(0.1))
            progress?(Double(i) / 10.0)
        }
        return nil
    }

    public func thumbnail(document: Document) async throws -> Image? {
        let data = try await thumbnailData(document: document)
        let image = Image(data: data)
        return image
    }

    public func thumbnailData(document: Document) async throws -> Data {
        let request = URLRequest(url: URL(string: "https://picsum.photos/id/\(document.id + 100)/1500/1000")!)

        do {
            let (data, _) = try await URLSession.shared.getData(for: request)

            return data
        } catch {
            Logger.networking.error("Unable to get preview document thumbnail (somehow): \(error)")
            throw error
        }
    }

    public nonisolated
    func thumbnailRequest(document: Document) throws -> URLRequest {
        URLRequest(url: URL(string: "https://picsum.photos/id/\(document.id + 100)/1500/1000")!)
    }

    public func uiSettings() async throws -> UISettings {
        try await UISettings(
            user: currentUser(),
            settings: UISettingsSettings(),
            permissions: permissions
        )
    }

    public nonisolated
    var delegate: (any URLSessionDelegate)?
    { nil }

    public func suggestions(documentId _: UInt) async throws -> Suggestions {
        Suggestions(correspondents: [], tags: [], documentTypes: [], storagePaths: [], dates: [])
    }
}

// MARK: - Support Types

public enum RepositoryError: Error {
    case documentNotFound
    case noUserLoggedIn
    case userNotFound
}

actor TransientDocumentSource: DocumentSource {
    typealias DocumentSequence = [Document]

    var sequence: DocumentSequence

    init(sequence: DocumentSequence) {
        self.sequence = sequence
    }

    public func fetch(limit: UInt) async -> [Document] {
        Array(sequence.prefix(Int(limit)))
    }

    public func hasMore() async -> Bool {
        false
    }
}
