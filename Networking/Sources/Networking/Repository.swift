//
//  Repository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.03.23.
//

import DataModel
import Foundation
import SwiftUI

public enum DocumentCreateError: Error {
  case tooLarge
}

public enum DocumentDownloadEvent {
  case progress
  case complete
}

@MainActor
public protocol Repository: Sendable {
  func update(document: Document) async throws -> Document
  func delete(document: Document) async throws
  func create(document: ProtoDocument, file: URL, filename: String) async throws

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

  func shareLinks(documentId: UInt) async throws -> [DataModel.ShareLink]

  func trash() async throws -> [Document]
  func restoreTrash(documents: [UInt]) async throws
  func emptyTrash(documents: [UInt]) async throws

  // @TODO: Remove UIImage
  func thumbnail(document: Document) async throws -> Image?
  func thumbnailData(document: Document) async throws -> Data

  nonisolated
    func thumbnailRequest(document: Document) throws -> URLRequest

  func download(documentID: UInt) async throws -> URL

  func download(documentID: UInt, original: Bool, progress: (@Sendable (Double) -> Void)?)
    async throws -> URL

  // Preferred entry point: callers that already hold a Document supply it so
  // the cache layer can use Document.modified as a staleness key without an
  // extra round trip.
  func download(
    document: Document, original: Bool,
    progress: (@Sendable (Double) -> Void)?
  ) async throws -> URL

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

  // MARK: Custom fields

  func customFields() async throws -> [CustomField]
  // @TODO: Implement other methods eventually

  // MARK: Server configuration

  func serverConfiguration() async throws -> ServerConfiguration
  func remoteVersion() async throws -> RemoteVersion

  // MARK: - Share links

  func create(shareLink: ProtoShareLink) async throws -> DataModel.ShareLink
  func delete(shareLink: DataModel.ShareLink) async throws

  // MARK: Others

  func currentUser() async throws -> User
  func users() async throws -> [User]
  func groups() async throws -> [UserGroup]
  func uiSettings() async throws -> UISettings
  func update(settings: UISettingsSettings) async throws

  func task(id: UInt) async throws -> PaperlessTask?

  // Cap to bound decode cost on installations with many unacknowledged tasks.
  // V10 backends honor the cap server-side; V9 backends serve the full array.
  func tasks(limit: UInt) async throws -> [PaperlessTask]

  func tasks() throws -> any TaskSource

  func acknowledge(tasks: [UInt]) async throws

  nonisolated
    var delegate: (any URLSessionDelegate)?
  { get }

  func supports(feature: BackendFeature) -> Bool
}

extension Repository {
  public func download(documentID: UInt) async throws -> URL {
    try await download(documentID: documentID, original: false, progress: nil)
  }

  public func download(documentID: UInt, original: Bool) async throws -> URL {
    try await download(documentID: documentID, original: original, progress: nil)
  }

  // Default impl for conformers that don't implement the Document-aware path:
  // fall back to the id-keyed call. ApiRepository overrides this directly to
  // avoid a redundant document fetch when threading staleness through the
  // ContentStore.
  public func download(
    document: Document, original: Bool = false,
    progress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> URL {
    try await download(
      documentID: document.id, original: original, progress: progress)
  }

  // Helper method documents with a title search
  public func documents(containsTitle title: String, limit: UInt = 10) async throws -> [Document] {
    var filter = FilterState.empty
    filter.searchText = title

    let source = try documents(filter: filter)
    return try await source.fetch(limit: limit)
  }
}

extension Repository {
  public func supports(feature: BackendFeature) -> Bool { true }
}

// - MARK: PagedSource
//
// Single abstraction for paged API resources. Both `DocumentSource` and
// `TaskSource` are typealiases for a `PagedSource` parameterised on the
// resource type, so that view models depend on one protocol shape.
public protocol PagedSource<Element>: Actor {
  associatedtype Element: Sendable
  func fetch(limit: UInt) async throws -> [Element]
  var isExhausted: Bool { get async }
  // Total number of items the server reports. `nil` until the first fetch
  // completes — and remains `nil` for sources with no notion of a server-side
  // total (e.g. unpaginated V9 task listings before the one-shot fetch).
  var totalCount: UInt? { get async }
}

public typealias DocumentSource = PagedSource<Document>
public typealias TaskSource = PagedSource<PaperlessTask>

public actor InMemoryTaskSource: PagedSource {
  public typealias Element = PaperlessTask

  private let initialCount: UInt
  private var remaining: [PaperlessTask]

  public init(_ tasks: [PaperlessTask]) {
    initialCount = UInt(tasks.count)
    remaining = tasks
  }

  public func fetch(limit: UInt) async -> [PaperlessTask] {
    let take = Int(min(UInt(remaining.count), limit))
    let head = Array(remaining.prefix(take))
    remaining.removeFirst(take)
    return head
  }

  public var isExhausted: Bool { remaining.isEmpty }
  public var totalCount: UInt? { initialCount }
}
