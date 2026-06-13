//
//  NeedsAuthRepository.swift
//  AppShared
//
//  A `Repository` decorator that watches outgoing calls for
//  `RequestError.unauthorized` (HTTP 401) and flips the wrapped connection's
//  `needsAuth` flag on `ConnectionManager`. The original error is always
//  re-thrown so call sites still see the failure — the flag drives the
//  user-visible recovery UI (banner + re-auth sheet); silent swallowing is
//  not the goal.
//
//  Known hole: Nuke's image pipeline fetches `thumbnailRequest(document:)`
//  URLRequests directly through its own session, bypassing this decorator.
//  Thumbnail 401s won't trigger the flag here — the first real `Repository`
//  call after token rejection (foreground refresh, list pull, mutation,
//  etc.) flips the state. Stage 13's custom `DataCaching` over `ContentStore`
//  is the natural place to close this gap.
//

import DataModel
import Foundation
import Networking
import SwiftUI
import os

@MainActor
public final class NeedsAuthRepository<Wrapped: Repository>: Repository {
  private let wrapped: Wrapped
  private let serverID: UUID
  private weak var connectionManager: ConnectionManager?

  public init(
    wrapping: Wrapped,
    serverID: UUID,
    connectionManager: ConnectionManager
  ) {
    self.wrapped = wrapping
    self.serverID = serverID
    self.connectionManager = connectionManager
  }

  private func intercept<T>(_ op: () async throws -> T) async throws -> T {
    do {
      return try await op()
    } catch let error as RequestError {
      if case .unauthorized = error {
        connectionManager?.markNeedsAuth(for: serverID)
      }
      throw error
    }
  }

  private func interceptSync<T>(_ op: () throws -> T) throws -> T {
    do {
      return try op()
    } catch let error as RequestError {
      if case .unauthorized = error {
        connectionManager?.markNeedsAuth(for: serverID)
      }
      throw error
    }
  }

  private var sourceCallback: @Sendable () -> Void {
    let manager = connectionManager
    let id = serverID
    return { [weak manager] in
      Task { @MainActor in
        manager?.markNeedsAuth(for: id)
      }
    }
  }

  // MARK: - Documents

  public func update(document: Document) async throws -> Document {
    try await intercept { try await wrapped.update(document: document) }
  }

  public func delete(document: Document) async throws {
    try await intercept { try await wrapped.delete(document: document) }
  }

  public func create(document: ProtoDocument, file: URL, filename: String) async throws {
    try await intercept {
      try await wrapped.create(document: document, file: file, filename: filename)
    }
  }

  public func document(id: UInt) async throws -> Document? {
    try await intercept { try await wrapped.document(id: id) }
  }

  public func document(asn: UInt) async throws -> Document? {
    try await intercept { try await wrapped.document(asn: asn) }
  }

  public func documents(filter: FilterState) throws
    -> InterceptingDocumentSource<Wrapped.Documents>
  {
    let source = try interceptSync { try wrapped.documents(filter: filter) }
    return InterceptingDocumentSource(wrapping: source, onUnauthorized: sourceCallback)
  }

  public func nextAsn() async throws -> UInt {
    try await intercept { try await wrapped.nextAsn() }
  }

  public func metadata(documentId: UInt) async throws -> Metadata {
    try await intercept { try await wrapped.metadata(documentId: documentId) }
  }

  public func notes(documentId: UInt) async throws -> [Document.Note] {
    try await intercept { try await wrapped.notes(documentId: documentId) }
  }

  public func createNote(documentId: UInt, note: ProtoDocument.Note) async throws
    -> [Document.Note]
  {
    try await intercept { try await wrapped.createNote(documentId: documentId, note: note) }
  }

  public func deleteNote(id: UInt, documentId: UInt) async throws -> [Document.Note] {
    try await intercept { try await wrapped.deleteNote(id: id, documentId: documentId) }
  }

  public func trash() async throws -> [Document] {
    try await intercept { try await wrapped.trash() }
  }

  public func restoreTrash(documents: [UInt]) async throws {
    try await intercept { try await wrapped.restoreTrash(documents: documents) }
  }

  public func emptyTrash(documents: [UInt]) async throws {
    try await intercept { try await wrapped.emptyTrash(documents: documents) }
  }

  // MARK: - Tags

  public func tag(id: UInt) async throws -> Tag? {
    try await intercept { try await wrapped.tag(id: id) }
  }

  public func create(tag: ProtoTag) async throws -> Tag {
    try await intercept { try await wrapped.create(tag: tag) }
  }

  public func update(tag: Tag) async throws -> Tag {
    try await intercept { try await wrapped.update(tag: tag) }
  }

  public func delete(tag: Tag) async throws {
    try await intercept { try await wrapped.delete(tag: tag) }
  }

  public func tags() async throws -> [Tag] {
    try await intercept { try await wrapped.tags() }
  }

  // MARK: - Correspondent

  public func correspondent(id: UInt) async throws -> Correspondent? {
    try await intercept { try await wrapped.correspondent(id: id) }
  }

  public func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
    try await intercept { try await wrapped.create(correspondent: correspondent) }
  }

  public func update(correspondent: Correspondent) async throws -> Correspondent {
    try await intercept { try await wrapped.update(correspondent: correspondent) }
  }

  public func delete(correspondent: Correspondent) async throws {
    try await intercept { try await wrapped.delete(correspondent: correspondent) }
  }

  public func correspondents() async throws -> [Correspondent] {
    try await intercept { try await wrapped.correspondents() }
  }

  // MARK: - Document type

  public func documentType(id: UInt) async throws -> DocumentType? {
    try await intercept { try await wrapped.documentType(id: id) }
  }

  public func create(documentType: ProtoDocumentType) async throws -> DocumentType {
    try await intercept { try await wrapped.create(documentType: documentType) }
  }

  public func update(documentType: DocumentType) async throws -> DocumentType {
    try await intercept { try await wrapped.update(documentType: documentType) }
  }

  public func delete(documentType: DocumentType) async throws {
    try await intercept { try await wrapped.delete(documentType: documentType) }
  }

  public func documentTypes() async throws -> [DocumentType] {
    try await intercept { try await wrapped.documentTypes() }
  }

  // MARK: - Thumbnails / downloads

  public func thumbnail(document: Document) async throws -> Image? {
    try await intercept { try await wrapped.thumbnail(document: document) }
  }

  public func thumbnailData(document: Document) async throws -> Data {
    try await intercept { try await wrapped.thumbnailData(document: document) }
  }

  public nonisolated func thumbnailRequest(document: Document) throws -> URLRequest {
    // Synchronous request construction; failures here aren't auth-related.
    try wrapped.thumbnailRequest(document: document)
  }

  public func download(
    document: Document, original: Bool,
    progress: (@Sendable (Double) -> Void)?
  ) async throws -> URL {
    try await intercept {
      try await wrapped.download(
        document: document, original: original, progress: progress)
    }
  }

  // MARK: - Suggestions

  public func suggestions(documentId: UInt) async throws -> Suggestions {
    try await intercept { try await wrapped.suggestions(documentId: documentId) }
  }

  // MARK: - Saved views

  public func savedViews() async throws -> [SavedView] {
    try await intercept { try await wrapped.savedViews() }
  }

  public func create(savedView: ProtoSavedView) async throws -> SavedView {
    try await intercept { try await wrapped.create(savedView: savedView) }
  }

  public func update(savedView: SavedView) async throws -> SavedView {
    try await intercept { try await wrapped.update(savedView: savedView) }
  }

  public func delete(savedView: SavedView) async throws {
    try await intercept { try await wrapped.delete(savedView: savedView) }
  }

  // MARK: - Storage paths

  public func storagePaths() async throws -> [StoragePath] {
    try await intercept { try await wrapped.storagePaths() }
  }

  public func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
    try await intercept { try await wrapped.create(storagePath: storagePath) }
  }

  public func update(storagePath: StoragePath) async throws -> StoragePath {
    try await intercept { try await wrapped.update(storagePath: storagePath) }
  }

  public func delete(storagePath: StoragePath) async throws {
    try await intercept { try await wrapped.delete(storagePath: storagePath) }
  }

  // MARK: - Custom fields

  public func customFields() async throws -> [CustomField] {
    try await intercept { try await wrapped.customFields() }
  }

  // MARK: - Server configuration

  public func serverConfiguration() async throws -> ServerConfiguration {
    try await intercept { try await wrapped.serverConfiguration() }
  }

  public func remoteVersion() async throws -> RemoteVersion {
    try await intercept { try await wrapped.remoteVersion() }
  }

  // MARK: - Share links

  public func shareLinks(documentId: UInt) async throws -> [DataModel.ShareLink] {
    try await intercept { try await wrapped.shareLinks(documentId: documentId) }
  }

  public func create(shareLink: ProtoShareLink) async throws -> DataModel.ShareLink {
    try await intercept { try await wrapped.create(shareLink: shareLink) }
  }

  public func delete(shareLink: DataModel.ShareLink) async throws {
    try await intercept { try await wrapped.delete(shareLink: shareLink) }
  }

  // MARK: - Users / groups / settings

  public func currentUser() async throws -> User {
    try await intercept { try await wrapped.currentUser() }
  }

  public func users() async throws -> [User] {
    try await intercept { try await wrapped.users() }
  }

  public func groups() async throws -> [UserGroup] {
    try await intercept { try await wrapped.groups() }
  }

  public func uiSettings() async throws -> UISettings {
    try await intercept { try await wrapped.uiSettings() }
  }

  public func update(settings: UISettingsSettings) async throws {
    try await intercept { try await wrapped.update(settings: settings) }
  }

  // MARK: - Tasks

  public func task(id: UInt) async throws -> PaperlessTask? {
    try await intercept { try await wrapped.task(id: id) }
  }

  public func tasks(limit: UInt) async throws -> [PaperlessTask] {
    try await intercept { try await wrapped.tasks(limit: limit) }
  }

  public func tasks() throws -> InterceptingTaskSource<Wrapped.Tasks> {
    let source = try interceptSync { try wrapped.tasks() }
    return InterceptingTaskSource(wrapping: source, onUnauthorized: sourceCallback)
  }

  public func acknowledge(tasks: [UInt]) async throws {
    try await intercept { try await wrapped.acknowledge(tasks: tasks) }
  }

  // MARK: - Infrastructure pass-throughs

  public nonisolated var delegate: (any URLSessionDelegate)? { wrapped.delegate }

  public func supports(feature: BackendFeature) -> Bool {
    wrapped.supports(feature: feature)
  }
}

// MARK: - PagedSource wrappers
//
// `documents(filter:)` and `tasks()` return actors that the caller drives
// asynchronously — their `fetch(limit:)` runs inside the source actor, so the
// outer Repository decorator's `intercept` doesn't see those calls. Wrap the
// returned sources so 401s during paging also flip the needs-auth flag.
//
// The wrappers are generic over the wrapped source so no `any` lives in their
// storage. Construction sites receive `any DocumentSource` / `any TaskSource`
// from the wrapped Repository's protocol method — Swift implicitly opens the
// existential when handing it to the generic init (SE-0352), the wrapper
// becomes `InterceptingDocumentSource<<opened>>`, and that erases back to
// `any DocumentSource` at the Repository return boundary.

public actor InterceptingDocumentSource<W: PagedSource>: PagedSource
where W.Element == Document {
  public typealias Element = Document
  private let wrapped: W
  private let onUnauthorized: @Sendable () -> Void

  public init(wrapping: W, onUnauthorized: @escaping @Sendable () -> Void) {
    self.wrapped = wrapping
    self.onUnauthorized = onUnauthorized
  }

  public func fetch(limit: UInt) async throws -> [Document] {
    do {
      return try await wrapped.fetch(limit: limit)
    } catch let error as RequestError {
      if case .unauthorized = error { onUnauthorized() }
      throw error
    }
  }

  public var isExhausted: Bool {
    get async { await wrapped.isExhausted }
  }

  public var totalCount: UInt? {
    get async { await wrapped.totalCount }
  }
}

public actor InterceptingTaskSource<W: PagedSource>: PagedSource
where W.Element == PaperlessTask {
  public typealias Element = PaperlessTask
  private let wrapped: W
  private let onUnauthorized: @Sendable () -> Void

  public init(wrapping: W, onUnauthorized: @escaping @Sendable () -> Void) {
    self.wrapped = wrapping
    self.onUnauthorized = onUnauthorized
  }

  public func fetch(limit: UInt) async throws -> [PaperlessTask] {
    do {
      return try await wrapped.fetch(limit: limit)
    } catch let error as RequestError {
      if case .unauthorized = error { onUnauthorized() }
      throw error
    }
  }

  public var isExhausted: Bool {
    get async { await wrapped.isExhausted }
  }

  public var totalCount: UInt? {
    get async { await wrapped.totalCount }
  }
}
