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
public protocol Repository<Documents, Tasks>: Sendable {
  // Concrete source types each conformer returns. Primary associated types
  // so `any Repository` (unconstrained) still works at storage sites — the
  // existential erases the source types back to `any PagedSource<Document>`
  // / `any PagedSource<PaperlessTask>` at call sites. Decorators like
  // `NeedsAuthRepository<Wrapped>` keep the types concrete: their wrappers
  // (`InterceptingDocumentSource<Wrapped.Documents>`) carry no existentials.
  associatedtype Documents: PagedSource where Documents.Element == Document
  associatedtype Tasks: PagedSource where Tasks.Element == PaperlessTask

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

  func documents(filter: FilterState) throws -> Documents

  /// The complete set of document IDs matching a query, in *id* order — backs
  /// the remote-delete reconcile, which consumes it as a set.
  ///
  /// The ordering is not the query's own: see ``pagedDocumentIDs(filter:)``.
  /// A caller that keeps the order wants ``orderedDocumentIDs(filter:)``.
  ///
  /// Deliberately has no default: only the API layer can express the cheap
  /// `fields=id` projection, and a default would let a conformer silently
  /// inherit the expensive full-list paging instead. Conformers that can't do
  /// better spell that out by calling `pagedDocumentIDs(filter:)`.
  func documentIDs(filter: FilterState) async throws -> [UInt]

  /// The complete list of document IDs matching a query **in the query's own
  /// sort order** — backs the saved-view membership sweep, which writes them
  /// straight into `query_order` as positions.
  ///
  /// Same projection concern as ``documentIDs(filter:)``, hence no default;
  /// conformers that can't project server-side call
  /// ``pagedOrderedDocumentIDs(filter:)``.
  func orderedDocumentIDs(filter: FilterState) async throws -> [UInt]

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

  // Conformers receive a full Document handle so the cache layer can use
  // Document.modified as a staleness key and Document.currentVersionID to
  // address the right server-side version row.
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

  func tasks() throws -> Tasks

  func acknowledge(tasks: [UInt]) async throws

  nonisolated
    var delegate: (any URLSessionDelegate)?
  { get }

  func supports(feature: BackendFeature) -> Bool
}

extension Repository {
  // Trampoline that supplies defaults for callers that don't need a progress
  // callback or always want the archive variant.
  //
  // Deliberately `download(document:original:)` and not
  // `download(document:original:progress:)`: default argument values don't
  // participate in witness matching, so the three-argument spelling would have
  // the same signature as the protocol requirement and become its default
  // witness — a body that calls itself. Conformers omitting the method would
  // then compile cleanly and infinitely recurse at runtime. Dropping `progress`
  // here makes the signature distinct, so it cannot satisfy the requirement and
  // the compiler keeps enforcing that every conformer implements it.
  public func download(
    document: Document, original: Bool = false
  ) async throws -> URL {
    try await download(document: document, original: original, progress: nil)
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

  /// The document-search encoding this backend understands. Use it both for
  /// requests and for the rules written into saved views, so the app does not
  /// store rule types the backend has deprecated.
  public var searchApi: FilterState.SearchApi {
    supports(feature: .tantivySimpleSearch) ? .tantivy : .legacy
  }

  /// Fallback for `documentIDs(filter:)`: page the full (Tier-1) list and map
  /// ids. Correct everywhere, but pulls whole `Document` payloads to read one
  /// field — backends that can project server-side should do that instead.
  ///
  /// Not a default implementation on purpose. It is a helper conformers opt
  /// into by name, so that inheriting the expensive path is a visible choice
  /// rather than the consequence of not writing anything.
  ///
  /// Pages over a *unique* ordering for the same reason `ApiRepository` does:
  /// the result is consumed as a set, and paging a non-unique one drops ids
  /// across page boundaries — which the remote-delete reconcile then reads as
  /// deletions. The `fields=id` projection is what can't be expressed here; the
  /// ordering can.
  public func pagedDocumentIDs(filter: FilterState) async throws -> [UInt] {
    var filter = filter
    filter.sortField = .other("id")
    filter.sortOrder = .ascending
    return try await pageIDs(filter: filter)
  }

  /// Fallback for `orderedDocumentIDs(filter:)`. Same expensive full-list paging
  /// as ``pagedDocumentIDs(filter:)``, but keeps the query's own sort — the
  /// caller is writing positions, so re-sorting would corrupt them.
  ///
  /// The ordering still has to be *unique* to page safely, which the id-order
  /// variant gets for free and this one cannot: every sort field the UI offers
  /// is non-unique. `ApiRepository` adds `id` as a secondary key; a conformer
  /// paging locally has no equivalent, so it sorts the assembled result by
  /// `(sortField, id)` only insofar as the backend already did.
  public func pagedOrderedDocumentIDs(filter: FilterState) async throws -> [UInt] {
    try await pageIDs(filter: filter)
  }

  private func pageIDs(filter: FilterState) async throws -> [UInt] {
    let source = try documents(filter: filter)
    var ids: [UInt] = []
    while true {
      let batch = try await source.fetch(limit: 1000)
      if batch.isEmpty { break }
      ids.append(contentsOf: batch.map(\.id))
      if await source.isExhausted { break }
    }
    return ids
  }
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

// Type-erased TaskSource. Lets a single conformer return one of several
// concrete `PagedSource` actors without exposing existentials at the
// protocol boundary — `Repository.Tasks` can then be a single named
// associated type. Used by `ApiRepository.tasks()` to wrap either
// `ApiPagedSource<ApiTaskV10, PaperlessTask>` (V10+ envelope) or
// `ApiTaskSourceV9` (V9 fallback) into the same return type.
//
// The erasure exists *only* to reconcile those two shapes. Once support for
// the V9 task shape is dropped, `tasks()` has a single concrete return type
// and this type can go away — `Repository.Tasks` would just name it directly,
// the way `Documents` already does.
public actor AnyTaskSource: PagedSource {
  public typealias Element = PaperlessTask

  private let _fetch: @Sendable (UInt) async throws -> [PaperlessTask]
  private let _isExhausted: @Sendable () async -> Bool
  private let _totalCount: @Sendable () async -> UInt?

  public init<S: PagedSource>(_ source: S) where S.Element == PaperlessTask {
    _fetch = { limit in try await source.fetch(limit: limit) }
    _isExhausted = { await source.isExhausted }
    _totalCount = { await source.totalCount }
  }

  public func fetch(limit: UInt) async throws -> [PaperlessTask] {
    try await _fetch(limit)
  }

  public var isExhausted: Bool {
    get async { await _isExhausted() }
  }

  public var totalCount: UInt? {
    get async { await _totalCount() }
  }
}
