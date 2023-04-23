//
//  Repository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.03.23.
//

import Foundation
import SwiftUI

protocol Repository {
    func updateDocument(_ document: Document) async throws -> Document
    func deleteDocument(_ document: Document) async throws
    func createDocument(_ document: ProtoDocument, file: URL) async throws

    func tag(id: UInt) async -> Tag?
    func createTag(_ tag: ProtoTag) async throws -> Tag
    func updateTag(_ tag: Tag) async throws -> Tag
    func deleteTag(_ tag: Tag) async throws

    func tags() async -> [Tag]

    func correspondent(id: UInt) async -> Correspondent?
    func correspondents() async -> [Correspondent]

    func documentType(id: UInt) async -> DocumentType?
    func documentTypes() async -> [DocumentType]

    func document(id: UInt) async -> Document?
    func documents(filter: FilterState) -> any DocumentSource

    // @TODO: Remove UIImage
    func thumbnail(document: Document) async -> (Bool, Image?)

    func download(documentID: UInt) async -> URL?

    func savedViews() async -> [SavedView]
    func createSavedView(_ view: ProtoSavedView) async throws -> SavedView
    func updateSavedView(_ view: SavedView) async throws -> SavedView
    func deleteSavedView(_ view: SavedView) async throws
}

class NullRepository: Repository {
    struct NotImplemented: Error {}

    func updateDocument(_ document: Document) async throws -> Document { document }
    func deleteDocument(_ document: Document) async throws {}
    func createDocument(_ document: ProtoDocument, file: URL) async throws {}

    func download(documentID: UInt) async -> URL? { return nil }

    func tag(id: UInt) async -> Tag? { return nil }
    func createTag(_ tag: ProtoTag) async throws -> Tag { throw NotImplemented() }
    func updateTag(_ tag: Tag) async throws -> Tag { throw NotImplemented() }
    func deleteTag(_ tag: Tag) async throws { throw NotImplemented() }

    func tags() async -> [Tag] { return [] }

    func correspondent(id: UInt) async -> Correspondent? { return nil }
    func correspondents() async -> [Correspondent] { return [] }

    func documentType(id: UInt) async -> DocumentType? { return nil }
    func documentTypes() async -> [DocumentType] { return [] }

    func document(id: UInt) async -> Document? { return nil }
    func documents(filter: FilterState) -> any DocumentSource {
        return NullDocumentSource()
    }

    func thumbnail(document: Document) async -> (Bool, Image?) { return (false, nil) }

    func savedViews() async -> [SavedView] { return [] }
    func createSavedView(_ view: ProtoSavedView) async throws -> SavedView { throw NotImplemented() }
    func updateSavedView(_ view: SavedView) async throws -> SavedView { view }
    func deleteSavedView(_ view: SavedView) async throws { throw NotImplemented() }
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
