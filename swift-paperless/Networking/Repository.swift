//
//  Repository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.03.23.
//

import Foundation
import SwiftUI

enum DocumentCreateError: DisplayableError {
    case tooLarge

    var message: String {
        switch self {
        case .tooLarge:
            return String(localized: .localizable(.documentCreateFailedTooLarge))
        }
    }

    var details: String? {
        switch self {
        case .tooLarge:
            return String(localized: .localizable(.documentCreateFailedTooLargeDetails))
        }
    }
}

actor AnyAsyncSequence<Element>: AsyncSequence & Sendable where Element: Sendable {
    typealias AsyncIterator = AnyAsyncIterator<Element>
    typealias Element = Element

    private let _makeAsyncIterator: @Sendable () -> AnyAsyncIterator<Element>

    actor AnyAsyncIterator<E>: AsyncIteratorProtocol, Sendable where E: Sendable {
        typealias Element = E

        private let _next: () async throws -> Element?

        init<I: AsyncIteratorProtocol>(itr: I) where I.Element == Element {
            var itr = itr
            _next = {
                try await itr.next()
            }
        }

        func next() async throws -> Element? {
            try await _next()
        }
    }

    init<S: AsyncSequence & Sendable>(seq: S) where S.Element == Element, S.AsyncIterator: Sendable {
        _makeAsyncIterator = { AnyAsyncIterator(itr: seq.makeAsyncIterator()) }
    }

    nonisolated func makeAsyncIterator() -> AnyAsyncIterator<Element> {
        _makeAsyncIterator()
    }
}

extension AsyncSequence where Self: Sendable, Element: Sendable, AsyncIterator: Sendable {
    func eraseToAnyAsyncSequence() -> AnyAsyncSequence<Element> {
        AnyAsyncSequence(seq: self)
    }
}

protocol Repository: Sendable, Actor {
    nonisolated
    func getIdentName() -> String?

    func update(document: Document) async throws -> Document
    func delete(document: Document) async throws
    func create(document: ProtoDocument, file: URL) async throws

    // MARK: Tags

    func tag(id: UInt) async throws -> Tag?
    func create(tag: ProtoTag) async throws -> Tag
    func update(tag: Tag) async throws -> Tag
    func delete(tag: Tag) async throws
    func tags() async throws -> [Tag]

    // MARK: Correspondent

    func correspondent(id: UInt) async throws -> Correspondent?
    func create(correspondent: ProtoCorrespondent) async throws -> Correspondent
    func update(correspondent: Correspondent) async throws -> Correspondent
    func delete(correspondent: Correspondent) async throws
    func correspondents() async throws -> [Correspondent]

    // MARK: Document type

    func documentType(id: UInt) async throws -> DocumentType?
    func create(documentType: ProtoDocumentType) async throws -> DocumentType
    func update(documentType: DocumentType) async throws -> DocumentType
    func delete(documentType: DocumentType) async throws
    func documentTypes() async throws -> [DocumentType]

    // MARK: Documents

    func document(id: UInt) async throws -> Document?
    func document(asn: UInt) async throws -> Document?

    func documents(filter: FilterState) throws -> any DocumentSource

    func nextAsn() async throws -> UInt

    // @TODO: Remove UIImage
    func thumbnail(document: Document) async throws -> Image?
    func thumbnailData(document: Document) async throws -> Data

    nonisolated
    func thumbnailRequest(document: Document) throws -> URLRequest

    func download(documentID: UInt) async throws -> URL?

    func suggestions(documentId: UInt) async throws -> Suggestions

    // MARK: Saved views

    func savedViews() async throws -> [SavedView]
    func create(savedView: ProtoSavedView) async throws -> SavedView
    func update(savedView: SavedView) async throws -> SavedView
    func delete(savedView: SavedView) async throws

    // MARK: Storage paths

    func storagePaths() async throws -> [StoragePath]
    func create(storagePath: ProtoStoragePath) async throws -> StoragePath
    func update(storagePath: StoragePath) async throws -> StoragePath
    func delete(storagePath: StoragePath) async throws

    func currentUser() async throws -> User
    func users() async throws -> [User]

    func task(id: UInt) async throws -> PaperlessTask?
    func tasks() async throws -> [PaperlessTask]

    func acknowledge(tasks: [UInt]) async throws
}

// - MARK: DocumentSource
protocol DocumentSource: Actor {
    func fetch(limit: UInt) async throws -> [Document]
    func hasMore() async -> Bool
}
