//
//  Repository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.03.23.
//

import AsyncAlgorithms
import DataModel
import Foundation
import SwiftUI

public enum DocumentCreateError: Error {
    case tooLarge
}

public actor AnyAsyncSequence<Element>: AsyncSequence & Sendable where Element: Sendable {
    public typealias AsyncIterator = AnyAsyncIterator<Element>
    public typealias Element = Element

    private let _makeAsyncIterator: @Sendable () -> AnyAsyncIterator<Element>

    public actor AnyAsyncIterator<E>: AsyncIteratorProtocol, Sendable where E: Sendable {
        public typealias Element = E

        private let _next: () async throws -> Element?

        public init<I: AsyncIteratorProtocol>(itr: I) where I.Element == Element {
            var itr = itr
            _next = {
                try await itr.next()
            }
        }

        public func next() async throws -> Element? {
            try await _next()
        }
    }

    public init<S: AsyncSequence & Sendable>(seq: S) where S.Element == Element, S.AsyncIterator: Sendable {
        _makeAsyncIterator = { AnyAsyncIterator(itr: seq.makeAsyncIterator()) }
    }

    public nonisolated func makeAsyncIterator() -> AnyAsyncIterator<Element> {
        _makeAsyncIterator()
    }
}

public extension AsyncSequence where Self: Sendable, Element: Sendable, AsyncIterator: Sendable {
    func eraseToAnyAsyncSequence() -> AnyAsyncSequence<Element> {
        AnyAsyncSequence(seq: self)
    }
}

public enum DocumentDownloadEvent {
    case progress
    case complete
}

public protocol Repository: Sendable, Actor {
    func update(document: Document) async throws -> Document
    func delete(document: Document) async throws
    func create(document: ProtoDocument, file: URL, filename: String) async throws ->Document

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

    func metadata(documentId: UInt) async throws -> Metadata

    func notes(documentId: UInt) async throws -> [Document.Note]
    func createNote(documentId: UInt, note: ProtoDocument.Note) async throws -> [Document.Note]
    func deleteNote(id: UInt, documentId: UInt) async throws -> [Document.Note]

    // @TODO: Remove UIImage
    func thumbnail(document: Document) async throws -> Image?
    func thumbnailData(document: Document) async throws -> Data

    nonisolated
    func thumbnailRequest(document: Document) throws -> URLRequest

    func download(documentID: UInt) async throws -> URL?

    func download(documentID: UInt, progress: (@Sendable (Double) -> Void)?) async throws -> URL?

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
    func groups() async throws -> [UserGroup]
    func uiSettings() async throws -> UISettings

    func task(id: UInt) async throws -> PaperlessTask?
    func tasks() async throws -> [PaperlessTask]

    func acknowledge(tasks: [UInt]) async throws

    nonisolated
    var delegate: (any URLSessionDelegate)? { get }
}

public extension Repository {
    func download(documentID: UInt) async throws -> URL? {
        try await download(documentID: documentID, progress: nil)
    }
}

// - MARK: DocumentSource
public protocol DocumentSource: Actor {
    func fetch(limit: UInt) async throws -> [Document]
    func hasMore() async -> Bool
}
