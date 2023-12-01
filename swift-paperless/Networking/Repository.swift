//
//  Repository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.03.23.
//

import Foundation
import SwiftUI

protocol Repository {
    func update(document: Document) async throws -> Document
    func delete(document: Document) async throws
    func create(document: ProtoDocument, file: URL) async throws

    // MARK: Tags

    func tag(id: UInt) async -> Tag?
    func create(tag: ProtoTag) async throws -> Tag
    func update(tag: Tag) async throws -> Tag
    func delete(tag: Tag) async throws
    func tags() async -> [Tag]

    // MARK: Correspondent

    func correspondent(id: UInt) async -> Correspondent?
    func create(correspondent: ProtoCorrespondent) async throws -> Correspondent
    func update(correspondent: Correspondent) async throws -> Correspondent
    func delete(correspondent: Correspondent) async throws
    func correspondents() async -> [Correspondent]

    // MARK: Document type

    func documentType(id: UInt) async -> DocumentType?
    func create(documentType: ProtoDocumentType) async throws -> DocumentType
    func update(documentType: DocumentType) async throws -> DocumentType
    func delete(documentType: DocumentType) async throws
    func documentTypes() async -> [DocumentType]

    // MARK: Documents

    func document(id: UInt) async -> Document?
    func document(asn: UInt) async -> Document?
    func documents(filter: FilterState) -> any DocumentSource

    func nextAsn() async -> UInt

    // @TODO: Remove UIImage
    func thumbnail(document: Document) async -> Image?
    func thumbnailData(document: Document) async -> Data?

    func download(documentID: UInt) async -> URL?

    func suggestions(documentId: UInt) async -> Suggestions

    // MARK: Saved views

    func savedViews() async -> [SavedView]
    func create(savedView: ProtoSavedView) async throws -> SavedView
    func update(savedView: SavedView) async throws -> SavedView
    func delete(savedView: SavedView) async throws

    // MARK: Storage paths

    func storagePaths() async -> [StoragePath]
    func create(storagePath: ProtoStoragePath) async throws -> StoragePath
    func update(storagePath: StoragePath) async throws -> StoragePath
    func delete(storagePath: StoragePath) async throws

    func currentUser() async throws -> User
    func users() async -> [User]

    func tasks() async -> [PaperlessTask]
}

class NullRepository: Repository {
    struct NotImplemented: Error {}

    func update(document: Document) async throws -> Document { document }
    func delete(document _: Document) async throws {}
    func create(document _: ProtoDocument, file _: URL) async throws {}

    func download(documentID _: UInt) async -> URL? { nil }

    func tag(id _: UInt) async -> Tag? { nil }
    func create(tag _: ProtoTag) async throws -> Tag { throw NotImplemented() }
    func update(tag _: Tag) async throws -> Tag { throw NotImplemented() }
    func delete(tag _: Tag) async throws { throw NotImplemented() }

    func tags() async -> [Tag] { [] }

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
    func documents(filter _: FilterState) -> any DocumentSource {
        NullDocumentSource()
    }

    func nextAsn() async -> UInt { 1 }

    func thumbnail(document _: Document) async -> Image? { nil }
    func thumbnailData(document _: Document) async -> Data? { nil }

    func savedViews() async -> [SavedView] { [] }
    func create(savedView _: ProtoSavedView) async throws -> SavedView { throw NotImplemented() }
    func update(savedView: SavedView) async throws -> SavedView { savedView }
    func delete(savedView _: SavedView) async throws { throw NotImplemented() }

    func storagePaths() async -> [StoragePath] { [] }
    func create(storagePath _: ProtoStoragePath) async throws -> StoragePath { throw NotImplemented() }
    func update(storagePath: StoragePath) async throws -> StoragePath { storagePath }
    func delete(storagePath _: StoragePath) async throws { throw NotImplemented() }

    func currentUser() async throws -> User { throw NotImplemented() }
    func users() async -> [User] { [] }

    func tasks() async -> [PaperlessTask] { [] }

    func suggestions(documentId _: UInt) async -> Suggestions { .init() }
}

// - MARK: DocumentSource
protocol DocumentSource {
    func fetch(limit: UInt) async -> [Document]
    func hasMore() async -> Bool
}

class NullDocumentSource: DocumentSource {
    func fetch(limit _: UInt) async -> [Document] { [] }
    func hasMore() async -> Bool { false }
}
