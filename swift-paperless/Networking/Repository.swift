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

    // @TODO: Remove UIImage
    func thumbnail(document: Document) async -> (Bool, Image?)
    func thumbnailData(document: Document) async -> Data?

    func download(documentID: UInt) async -> URL?

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
    func delete(document: Document) async throws {}
    func create(document: ProtoDocument, file: URL) async throws {}

    func download(documentID: UInt) async -> URL? { return nil }

    func tag(id: UInt) async -> Tag? { return nil }
    func create(tag: ProtoTag) async throws -> Tag { throw NotImplemented() }
    func update(tag: Tag) async throws -> Tag { throw NotImplemented() }
    func delete(tag: Tag) async throws { throw NotImplemented() }

    func tags() async -> [Tag] { return [] }

    func correspondent(id: UInt) async -> Correspondent? { return nil }
    func create(correspondent: ProtoCorrespondent) async throws -> Correspondent { throw NotImplemented() }
    func update(correspondent: Correspondent) async throws -> Correspondent { throw NotImplemented() }
    func delete(correspondent: Correspondent) async throws {}

    func correspondents() async -> [Correspondent] { return [] }

    func documentType(id: UInt) async -> DocumentType? { return nil }
    func create(documentType: ProtoDocumentType) async throws -> DocumentType { throw NotImplemented() }
    func update(documentType: DocumentType) async throws -> DocumentType { throw NotImplemented() }
    func delete(documentType: DocumentType) async throws {}
    func documentTypes() async -> [DocumentType] { return [] }

    func document(id: UInt) async -> Document? { return nil }
    func document(asn: UInt) async -> Document? { return nil }
    func documents(filter: FilterState) -> any DocumentSource {
        return NullDocumentSource()
    }

    func thumbnail(document: Document) async -> (Bool, Image?) { return (false, nil) }
    func thumbnailData(document: Document) async -> Data? { return nil }

    func savedViews() async -> [SavedView] { return [] }
    func create(savedView: ProtoSavedView) async throws -> SavedView { throw NotImplemented() }
    func update(savedView: SavedView) async throws -> SavedView { savedView }
    func delete(savedView: SavedView) async throws { throw NotImplemented() }

    func storagePaths() async -> [StoragePath] { return [] }
    func create(storagePath: ProtoStoragePath) async throws -> StoragePath { throw NotImplemented() }
    func update(storagePath: StoragePath) async throws -> StoragePath { storagePath }
    func delete(storagePath: StoragePath) async throws { throw NotImplemented() }

    func currentUser() async throws -> User { throw NotImplemented() }
    func users() async -> [User] { [] }

    func tasks() async -> [PaperlessTask] { [] }
}

// - MARK: DocumentSource
protocol DocumentSource {
    func fetch(limit: UInt) async -> [Document]
    func hasMore() async -> Bool
}

class NullDocumentSource: DocumentSource {
    func fetch(limit: UInt) async -> [Document] { return [] }
    func hasMore() async -> Bool { return false }
}
