import DataModel
import Foundation
import os
import SwiftUI

actor TransientRepository {
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

    private var nextId: UInt = 1
    private var currentLoggedInUser: User?

    init() {
        documents = [:]
        tags = [:]
        documentTypes = [:]
        correspondents = [:]
        storagePaths = [:]
        tasks = []
        users = []
        groups = []
        savedViews = [:]

        notesByDocument = [:]
    }

    private func generateId() -> UInt {
        defer { nextId += 1 }
        return nextId
    }

    // MARK: - User Management

    /// Adds a user to the repository's user list
    func addUser(_ user: User) {
        users.append(user)
    }

    /// Logs in a user by ID. The user must exist in the repository's user list.
    /// - Parameter userId: The ID of the user to log in
    /// - Throws: RepositoryError.userNotFound if the user doesn't exist
    func login(userId: UInt) throws {
        guard let user = users.first(where: { $0.id == userId }) else {
            throw RepositoryError.userNotFound
        }
        currentLoggedInUser = user
    }

    /// Logs in a user by username. The user must exist in the repository's user list.
    /// - Parameter username: The username of the user to log in
    /// - Throws: RepositoryError.userNotFound if the user doesn't exist
    func login(username: String) throws {
        guard let user = users.first(where: { $0.username == username }) else {
            throw RepositoryError.userNotFound
        }
        currentLoggedInUser = user
    }

    /// Logs out the current user
    func logout() {
        currentLoggedInUser = nil
    }
}

// MARK: - Repository Conformance

extension TransientRepository: Repository {
    // MARK: - Documents

    func update(document: Document) async throws -> Document {
        documents[document.id] = document
        return document
    }

    func document(id: UInt) async throws -> Document? {
        documents[id]
    }

    func document(asn: UInt) async throws -> Document? {
        documents.first(where: { $0.value.asn == asn })?.value
    }

    func documents(filter _: FilterState) throws -> any DocumentSource {
        TransientDocumentSource(sequence: documents.map(\.value))
    }

    func nextAsn() async throws -> UInt {
        (documents.compactMap(\.value.asn).max() ?? 0) + 1
    }

    func delete(document: Document) async throws {
        documents.removeValue(forKey: document.id)
    }

    func create(document: ProtoDocument, file _: URL, filename _: String) async throws ->Document {
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
        return newDoc
    }

    // MARK: - Tags

    func tag(id: UInt) async throws -> Tag? {
        tags[id]
    }

    func tags() async throws -> [Tag] {
        tags.map(\.value)
    }

    func create(tag: ProtoTag) async throws -> Tag {
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

    func update(tag: Tag) async throws -> Tag {
        tags[tag.id] = tag
        return tag
    }

    func delete(tag: Tag) async throws {
        tags.removeValue(forKey: tag.id)
    }

    // MARK: - Correspondents

    func correspondent(id: UInt) async throws -> Correspondent? {
        correspondents[id]
    }

    func correspondents() async throws -> [Correspondent] {
        correspondents.map(\.value)
    }

    func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
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

    func update(correspondent: Correspondent) async throws -> Correspondent {
        correspondents[correspondent.id] = correspondent
        return correspondent
    }

    func delete(correspondent: Correspondent) async throws {
        correspondents.removeValue(forKey: correspondent.id)
    }

    // MARK: - Document Types

    func documentType(id: UInt) async throws -> DocumentType? {
        documentTypes[id]
    }

    func create(documentType: ProtoDocumentType) async throws -> DocumentType {
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

    func update(documentType: DocumentType) async throws -> DocumentType {
        documentTypes[documentType.id] = documentType
        return documentType
    }

    func delete(documentType: DocumentType) async throws {
        documentTypes.removeValue(forKey: documentType.id)
    }

    func documentTypes() async throws -> [DocumentType] {
        documentTypes.map(\.value)
    }

    // MARK: - Storage Paths

    func storagePaths() async throws -> [StoragePath] {
        storagePaths.map(\.value)
    }

    func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
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

    func update(storagePath: StoragePath) async throws -> StoragePath {
        storagePaths[storagePath.id] = storagePath
        return storagePath
    }

    func delete(storagePath: StoragePath) async throws {
        storagePaths.removeValue(forKey: storagePath.id)
    }

    // MARK: - Saved Views

    func savedViews() async throws -> [SavedView] {
        savedViews.map(\.value)
    }

    func create(savedView: ProtoSavedView) async throws -> SavedView {
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

    func update(savedView: SavedView) async throws -> SavedView {
        savedViews[savedView.id] = savedView
        return savedView
    }

    func delete(savedView: SavedView) async throws {
        savedViews.removeValue(forKey: savedView.id)
    }

    // MARK: - Users and Groups

    func currentUser() async throws -> User {
        if let currentLoggedInUser {
            return currentLoggedInUser
        }
        throw RepositoryError.noUserLoggedIn
    }

    func users() async throws -> [User] {
        users
    }

    func groups() async throws -> [UserGroup] {
        groups
    }

    // MARK: - Tasks

    func tasks() async throws -> [PaperlessTask] {
        tasks
    }

    func task(id: UInt) async throws -> PaperlessTask? {
        tasks.first { $0.id == id }
    }

    func acknowledge(tasks ids: [UInt]) async throws {
        for id in ids {
            if let index = tasks.firstIndex(where: { $0.id == id }) {
                var task = tasks[index]
                task.acknowledged = true
                tasks[index] = task
            }
        }
    }

    // MARK: - Document Operations

    func metadata(documentId _: UInt) async throws -> Metadata {
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

    func notes(documentId: UInt) async throws -> [Document.Note] {
        notesByDocument[documentId, default: []]
    }

    func createNote(documentId: UInt, note: ProtoDocument.Note) async throws -> [Document.Note] {
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

    func deleteNote(id: UInt, documentId: UInt) async throws -> [Document.Note] {
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

    func download(documentID _: UInt, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL? {
        // Simulate download progress
        for i in 1 ... 10 {
            try await Task.sleep(for: .seconds(0.1))
            progress?(Double(i) / 10.0)
        }
        return nil
    }

    func thumbnail(document _: Document) async throws -> Image? {
        nil
    }

    func thumbnailData(document _: Document) async throws -> Data {
        Data()
    }

    nonisolated
    func thumbnailRequest(document _: Document) throws -> URLRequest {
        URLRequest(url: URL(string: "about:blank")!)
    }

    func uiSettings() async throws -> UISettings {
        try await UISettings(
            user: currentUser(),
            settings: UISettingsSettings(),
            permissions: UserPermissions.full
        )
    }

    nonisolated
    var delegate: (any URLSessionDelegate)? { nil }

    func suggestions(documentId _: UInt) async throws -> Suggestions {
        Suggestions(correspondents: [], tags: [], documentTypes: [], storagePaths: [], dates: [])
    }
}

// MARK: - Support Types

enum RepositoryError: Error {
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

    func fetch(limit: UInt) async -> [Document] {
        Array(sequence.prefix(Int(limit)))
    }

    func hasMore() async -> Bool {
        false
    }
}
