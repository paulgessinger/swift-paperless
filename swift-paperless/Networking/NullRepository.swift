//
//  NullRepository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.05.2024.
//

import DataModel
import SwiftUI

actor NullRepository: Repository {
    struct NotImplemented: Error {}

    func update(document _: Document) async throws -> Document { throw NotImplemented() }
    func delete(document _: Document) async throws { throw NotImplemented() }
    func create(document _: ProtoDocument, file _: URL) async throws { throw NotImplemented() }

    func download(documentID _: UInt, progress _: (@Sendable (Double) -> Void)? = nil) async throws -> URL? { nil }

    func tag(id _: UInt) async -> Tag? { nil }
    func create(tag _: ProtoTag) async throws -> Tag { throw NotImplemented() }
    func update(tag _: Tag) async throws -> Tag { throw NotImplemented() }
    func delete(tag _: Tag) async throws { throw NotImplemented() }

    func tags() async -> [Tag] { [] }
    func uiSettings() async throws -> UISettings {
        UISettings(user: User(id: 0, isSuperUser: false, username: "nobody"), permissions: .empty)
    }

    func correspondent(id _: UInt) async -> Correspondent? { nil }
    func create(correspondent _: ProtoCorrespondent) async throws -> Correspondent { throw NotImplemented() }
    func update(correspondent _: Correspondent) async throws -> Correspondent { throw NotImplemented() }
    func delete(correspondent _: Correspondent) async throws {}

    func correspondents() async -> [Correspondent] { [] }

    func documentType(id _: UInt) async -> DocumentType? { nil }
    func create(documentType _: ProtoDocumentType) async throws -> DocumentType { throw NotImplemented() }
    func update(documentType _: DocumentType) async throws -> DocumentType { throw NotImplemented() }
    func delete(documentType _: DocumentType) async throws {}
    func documentTypes() async -> [DocumentType] { [] }

    func document(id _: UInt) async -> Document? { nil }
    func document(asn _: UInt) async -> Document? { nil }

    func metadata(documentId _: UInt) async throws -> Metadata { throw NotImplemented() }

    func createNote(documentId _: UInt, note _: ProtoDocument.Note) async throws -> [Document.Note] { [] }
    func deleteNote(id _: UInt, documentId _: UInt) async throws -> [Document.Note] { [] }

    nonisolated func documents(filter _: FilterState) -> any DocumentSource {
        NullDocumentSource()
    }

    func nextAsn() async -> UInt { 1 }

    func thumbnail(document _: Document) async -> Image? { nil }
    func thumbnailData(document _: Document) async throws -> Data { throw NotImplemented() }

    nonisolated
    func thumbnailRequest(document _: Document) throws -> URLRequest { throw NotImplemented() }

    func savedViews() async -> [SavedView] { [] }
    func create(savedView _: ProtoSavedView) async throws -> SavedView { throw NotImplemented() }
    func update(savedView: SavedView) async throws -> SavedView { savedView }
    func delete(savedView _: SavedView) async throws { throw NotImplemented() }

    func storagePaths() async -> [StoragePath] { [] }
    func create(storagePath _: ProtoStoragePath) async throws -> StoragePath { throw NotImplemented() }
    func update(storagePath: StoragePath) async throws -> StoragePath { storagePath }
    func delete(storagePath _: StoragePath) async throws { throw NotImplemented() }

    func currentUser() async throws -> User {
        throw NotImplemented()
    }

    func users() async -> [User] { [] }
    func groups() async throws -> [UserGroup] { [] }

    func task(id _: UInt) async throws -> PaperlessTask? { nil }
    func tasks() async -> [PaperlessTask] { [] }

    func acknowledge(tasks _: [UInt]) async throws {}

    func suggestions(documentId _: UInt) async -> Suggestions { .init() }

    nonisolated
    var delegate: (any URLSessionDelegate)? { nil }
}

actor NullDocumentSource: DocumentSource {
    func fetch(limit _: UInt) async throws -> [Document] { [] }
    func hasMore() async -> Bool { false }
}
