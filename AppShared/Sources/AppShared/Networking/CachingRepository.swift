//
//  CachingRepository.swift
//  AppShared
//
//  A `Repository` decorator that serves the small "element" collections (tags,
//  correspondents, document types, storage paths, saved views, users, groups,
//  custom fields, current user / UI settings, server config) from the local
//  GRDB cache, and exposes a separate `sync` (network → DB) via
//  `CachingBackend`.
//
//  Layering: this sits *outside* `NeedsAuthRepository` —
//  `CachingRepository(wrapping: NeedsAuthRepository(wrapping: ApiRepository))` —
//  so reads come from the cache while `sync`'s network calls still flow through
//  the 401 → needs-auth interception.
//
//  Read methods are pure cache reads and never hit the network, except the
//  single-element getters (`tag(id:)` etc.) which fall back to the network +
//  write-through to resolve a referenced id absent from the cached set.
//  Element mutations are pessimistic: forward to the server, then write the
//  confirmed value through to the cache. Everything document/task related is
//  forwarded unchanged — those caches are later stages.
//

import Common
import DataModel
import Foundation
import Networking
import Persistence
import SwiftUI
import os

/// The cache control surface the store reaches for, kept off the `Repository`
/// protocol (which stays technology-agnostic). A repository that isn't a
/// `CachingBackend` (preview, Share Extension, tests) makes the store fall back
/// to direct-network behavior.
@MainActor
public protocol CachingBackend: AnyObject, Sendable {
  /// Fetch every element collection from the network and reconcile it into the
  /// local cache. Throws if the sync as a whole fails (e.g. offline); a single
  /// resource the user lacks permission for is skipped, not fatal.
  func syncElements() async throws

  /// Eager full-fill of a document list (Stage 8 v1): await page 1 (so the first
  /// window + an exact count land synchronously), write it as the query's order,
  /// then background-page the rest of the query to the cache. The returned
  /// ``QueryFillHandle`` carries the `QueryKey` the list observes and a cancel
  /// handle for the in-flight fill. Throws if page 1 fails (offline → the list
  /// falls back to whatever is already cached).
  func fillQuery(filter: FilterState) async throws -> QueryFillHandle

  /// Remote-delete reconcile (R2): fetch the server's authoritative live id set
  /// and drop every cached document absent from it — the FK cascade removes them
  /// from every cached query_order. No-op when nothing is cached. Paperless has
  /// no deletion feed, so this periodic sweep is how deletes (and trashings)
  /// disappear locally.
  func reconcileDocumentDeletions() async throws

  /// The shared database and the active server this repository caches into.
  /// `DocumentStore` reads these to point its `ElementStore` projection at the
  /// same `(database, serverID)` the writes land in, so the live observation
  /// sees them.
  var database: Database { get }
  var serverID: UUID { get }
}

enum CachingRepositoryError: Error {
  /// A pure cache read found nothing for a non-optional resource. The store's
  /// hydrate path tolerates this (cold cache); `sync` then fills it.
  case cacheMiss
}

@MainActor
public final class CachingRepository<Wrapped: Repository>: Repository, CachingBackend {
  let wrapped: Wrapped
  public let database: Database
  public let serverID: UUID

  public init(wrapping: Wrapped, database: Database, serverID: UUID) {
    wrapped = wrapping
    self.database = database
    self.serverID = serverID
  }

  // MARK: - CachingBackend

  public func syncElements() async throws {
    // Sync UI settings *first*: its permission matrix gates the rest, so we
    // don't ask the server for collections the user can't view (doomed 403s).
    // When the matrix is unavailable (uiSettings failed and nothing is cached),
    // `gate` is nil and we fetch everything, relying on the per-resource
    // 403/401-skip in `syncCollection` as a fallback.
    let gate = await syncUISettings()
    func canView(_ resource: UserPermissions.Resource) -> Bool {
      gate?.test(.view, for: resource) ?? true
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      if canView(.tag) {
        group.addTask { [self] in
          try await syncCollection(TagRecord.self) { try await wrapped.tags() }
        }
      }
      if canView(.correspondent) {
        group.addTask { [self] in
          try await syncCollection(CorrespondentRecord.self) {
            try await wrapped.correspondents()
          }
        }
      }
      if canView(.documentType) {
        group.addTask { [self] in
          try await syncCollection(DocumentTypeRecord.self) {
            try await wrapped.documentTypes()
          }
        }
      }
      if canView(.storagePath) {
        group.addTask { [self] in
          try await syncCollection(StoragePathRecord.self) {
            try await wrapped.storagePaths()
          }
        }
      }
      if canView(.savedView) {
        group.addTask { [self] in
          try await syncCollection(SavedViewRecord.self) { try await wrapped.savedViews() }
        }
      }
      if canView(.user) {
        group.addTask { [self] in
          try await syncCollection(UserRecord.self) { try await wrapped.users() }
        }
      }
      if canView(.group) {
        group.addTask { [self] in
          try await syncCollection(UserGroupRecord.self) { try await wrapped.groups() }
        }
      }
      if canView(.customField) {
        group.addTask { [self] in
          try await syncCollection(CustomFieldRecord.self) {
            try await wrapped.customFields()
          }
        }
      }
      group.addTask { [self] in try await syncServerConfiguration() }

      for try await _ in group {}
    }
  }

  public func fillQuery(filter: FilterState) async throws -> QueryFillHandle {
    let key = QueryKey(serverID: serverID, filter: filter)
    let source = try wrapped.documents(filter: filter)
    let pageSize = Endpoint.defaultDocumentPageSize

    // Page 1 awaited: first window on screen + exact scrollbar count.
    let firstPage = try await source.fetch(limit: pageSize)
    let total = await source.totalCount
    try database.writeQueryPage(
      queryKey: key, serverID: serverID, documents: firstPage,
      startPosition: 0, totalCount: total, replaceAll: true, projectionLevel: .metadata)

    // Background-page the rest to disk (append). When this completes the whole
    // view is local; scrolling then needs no network (v1).
    let database = database
    let serverID = serverID
    let firstCount = firstPage.count
    let task = Task.detached(priority: .utility) {
      var position = firstCount
      do {
        while !Task.isCancelled {
          if await source.isExhausted { break }
          let batch = try await source.fetch(limit: pageSize)
          if batch.isEmpty { break }
          try database.writeQueryPage(
            queryKey: key, serverID: serverID, documents: batch,
            startPosition: position, totalCount: await source.totalCount,
            replaceAll: false, projectionLevel: .metadata)
          position += batch.count
        }
      } catch is CancellationError {
      } catch {
        Logger.shared.error("Background query fill failed: \(error)")
      }
    }
    return QueryFillHandle(queryKey: key, totalCount: total, fillTask: task)
  }

  private func syncCollection<R: ElementRecord>(
    _ type: R.Type, _ fetch: () async throws -> [R.Domain]
  ) async throws {
    do {
      let domains = try await fetch()
      try database.replaceElements(domains, of: type, serverID: serverID)
    } catch let error as RequestError where Self.isSkippable(error) {
      Logger.shared.info(
        "Skipping \(R.databaseTableName, privacy: .public) sync: \(error)")
    }
  }

  /// Fetch the UI settings singleton and return its permission matrix to gate
  /// the rest of the sync. Never throws: on any failure it falls back to the
  /// last cached matrix, or `nil` if none exists (caller then fetches every
  /// collection and relies on per-resource 403/401-skip, as before). A
  /// uiSettings failure therefore degrades gating without aborting the sync.
  private func syncUISettings() async -> UserPermissions? {
    do {
      let settings = try await wrapped.uiSettings()
      try database.setUISettings(settings, serverID: serverID)
      return settings.permissions
    } catch {
      Logger.shared.info(
        "uiSettings sync failed (\(error)); gating sync on cached permissions")
      return try? database.uiSettings(serverID: serverID)?.permissions
    }
  }

  private func syncServerConfiguration() async throws {
    do {
      let config = try await wrapped.serverConfiguration()
      try database.setServerConfiguration(config, serverID: serverID)
    } catch let error as RequestError where Self.isSkippable(error) {
      Logger.shared.info("Skipping serverConfiguration sync: \(error)")
    }
  }

  /// 401 already flips needs-auth via the wrapped decorator; 403 means the user
  /// lacks permission for that one resource. Neither should fail the whole sync.
  private static func isSkippable(_ error: RequestError) -> Bool {
    switch error {
    case .forbidden, .unauthorized: true
    default: false
    }
  }

  // MARK: - Element reads (cache)

  public func tags() async throws -> [Tag] {
    try database.elements(TagRecord.self, serverID: serverID)
  }

  public func correspondents() async throws -> [Correspondent] {
    try database.elements(CorrespondentRecord.self, serverID: serverID)
  }

  public func documentTypes() async throws -> [DocumentType] {
    try database.elements(DocumentTypeRecord.self, serverID: serverID)
  }

  public func storagePaths() async throws -> [StoragePath] {
    try database.elements(StoragePathRecord.self, serverID: serverID)
  }

  public func savedViews() async throws -> [SavedView] {
    try database.elements(SavedViewRecord.self, serverID: serverID)
  }

  public func users() async throws -> [User] {
    try database.elements(UserRecord.self, serverID: serverID)
  }

  public func groups() async throws -> [UserGroup] {
    try database.elements(UserGroupRecord.self, serverID: serverID)
  }

  public func customFields() async throws -> [CustomField] {
    try database.elements(CustomFieldRecord.self, serverID: serverID)
  }

  public func currentUser() async throws -> User {
    guard let user = try database.uiSettings(serverID: serverID)?.user else {
      throw CachingRepositoryError.cacheMiss
    }
    return user
  }

  public func uiSettings() async throws -> UISettings {
    guard let settings = try database.uiSettings(serverID: serverID) else {
      throw CachingRepositoryError.cacheMiss
    }
    return settings
  }

  public func serverConfiguration() async throws -> ServerConfiguration {
    guard let config = try database.serverConfiguration(serverID: serverID) else {
      throw CachingRepositoryError.cacheMiss
    }
    return config
  }

  // MARK: - Single-element getters (cache-first + network fallback + write-through)

  public func tag(id: UInt) async throws -> Tag? {
    if let cached = try database.element(TagRecord.self, serverID: serverID, id: id) {
      return cached
    }
    guard let fetched = try await wrapped.tag(id: id) else { return nil }
    try database.upsertElement(fetched, of: TagRecord.self, serverID: serverID)
    return fetched
  }

  public func correspondent(id: UInt) async throws -> Correspondent? {
    if let cached = try database.element(CorrespondentRecord.self, serverID: serverID, id: id) {
      return cached
    }
    guard let fetched = try await wrapped.correspondent(id: id) else { return nil }
    try database.upsertElement(fetched, of: CorrespondentRecord.self, serverID: serverID)
    return fetched
  }

  public func documentType(id: UInt) async throws -> DocumentType? {
    if let cached = try database.element(DocumentTypeRecord.self, serverID: serverID, id: id) {
      return cached
    }
    guard let fetched = try await wrapped.documentType(id: id) else { return nil }
    try database.upsertElement(fetched, of: DocumentTypeRecord.self, serverID: serverID)
    return fetched
  }

  // MARK: - Element mutations (pessimistic: forward + write-through)

  public func create(tag: ProtoTag) async throws -> Tag {
    let created = try await wrapped.create(tag: tag)
    try database.upsertElement(created, of: TagRecord.self, serverID: serverID)
    return created
  }

  public func update(tag: Tag) async throws -> Tag {
    let updated = try await wrapped.update(tag: tag)
    try database.upsertElement(updated, of: TagRecord.self, serverID: serverID)
    return updated
  }

  public func delete(tag: Tag) async throws {
    try await wrapped.delete(tag: tag)
    try database.deleteElement(TagRecord.self, serverID: serverID, id: tag.id)
  }

  public func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
    let created = try await wrapped.create(correspondent: correspondent)
    try database.upsertElement(created, of: CorrespondentRecord.self, serverID: serverID)
    return created
  }

  public func update(correspondent: Correspondent) async throws -> Correspondent {
    let updated = try await wrapped.update(correspondent: correspondent)
    try database.upsertElement(updated, of: CorrespondentRecord.self, serverID: serverID)
    return updated
  }

  public func delete(correspondent: Correspondent) async throws {
    try await wrapped.delete(correspondent: correspondent)
    try database.deleteElement(CorrespondentRecord.self, serverID: serverID, id: correspondent.id)
  }

  public func create(documentType: ProtoDocumentType) async throws -> DocumentType {
    let created = try await wrapped.create(documentType: documentType)
    try database.upsertElement(created, of: DocumentTypeRecord.self, serverID: serverID)
    return created
  }

  public func update(documentType: DocumentType) async throws -> DocumentType {
    let updated = try await wrapped.update(documentType: documentType)
    try database.upsertElement(updated, of: DocumentTypeRecord.self, serverID: serverID)
    return updated
  }

  public func delete(documentType: DocumentType) async throws {
    try await wrapped.delete(documentType: documentType)
    try database.deleteElement(DocumentTypeRecord.self, serverID: serverID, id: documentType.id)
  }

  public func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
    let created = try await wrapped.create(storagePath: storagePath)
    try database.upsertElement(created, of: StoragePathRecord.self, serverID: serverID)
    return created
  }

  public func update(storagePath: StoragePath) async throws -> StoragePath {
    let updated = try await wrapped.update(storagePath: storagePath)
    try database.upsertElement(updated, of: StoragePathRecord.self, serverID: serverID)
    return updated
  }

  public func delete(storagePath: StoragePath) async throws {
    try await wrapped.delete(storagePath: storagePath)
    try database.deleteElement(StoragePathRecord.self, serverID: serverID, id: storagePath.id)
  }

  public func create(savedView: ProtoSavedView) async throws -> SavedView {
    let created = try await wrapped.create(savedView: savedView)
    try database.upsertElement(created, of: SavedViewRecord.self, serverID: serverID)
    return created
  }

  public func update(savedView: SavedView) async throws -> SavedView {
    let updated = try await wrapped.update(savedView: savedView)
    try database.upsertElement(updated, of: SavedViewRecord.self, serverID: serverID)
    return updated
  }

  public func delete(savedView: SavedView) async throws {
    try await wrapped.delete(savedView: savedView)
    try database.deleteElement(SavedViewRecord.self, serverID: serverID, id: savedView.id)
  }

  // MARK: - Documents (Stage 8: pessimistic write-through + cache fallback)

  public func update(document: Document) async throws -> Document {
    let updated = try await wrapped.update(document: document)
    // Write the confirmed metadata through; the join observation repaints the row
    // in place. Written at `.metadata` so the non-downgrade guard preserves an
    // existing Tier-2 row's detail/permissions (a metadata edit doesn't change
    // them; permissions edits reconcile on the next detail fetch). Ordering under
    // the active sort isn't recomputed offline — mark affected queries stale.
    try database.upsertDocument(updated, serverID: serverID, projectionLevel: .metadata)
    try database.markQueriesOrderStale(containing: updated.id, serverID: serverID)
    return updated
  }

  public func delete(document: Document) async throws {
    try await wrapped.delete(document: document)
    // FK cascade removes it from every cached query_order.
    try database.deleteDocuments(serverID: serverID, removedIDs: [document.id])
  }

  public func create(document: ProtoDocument, file: URL, filename: String) async throws {
    try await wrapped.create(document: document, file: file, filename: filename)
  }

  public func document(id: UInt) async throws -> Document? {
    do {
      guard let fetched = try await wrapped.document(id: id) else {
        // Gone on the server — drop from cache (cascade clears its query_order).
        try database.deleteDocuments(serverID: serverID, removedIDs: [id])
        return nil
      }
      // A full-detail fetch — upgrade the row to Tier-2.
      try database.upsertDocument(fetched, serverID: serverID, projectionLevel: .detail)
      return fetched
    } catch {
      // Offline/transient: serve the last-known cached row (Tier-1 or Tier-2)
      // rather than failing the open. Mirrors the element offline-first policy.
      if let cached = try database.document(serverID: serverID, id: id) {
        Logger.shared.info("document(id:) network failed (\(error)); serving cached")
        return cached
      }
      throw error
    }
  }

  public func document(asn: UInt) async throws -> Document? {
    do {
      guard let fetched = try await wrapped.document(asn: asn) else { return nil }
      try database.upsertDocument(fetched, serverID: serverID, projectionLevel: .detail)
      return fetched
    } catch {
      if let cached = try database.document(serverID: serverID, asn: asn) {
        Logger.shared.info("document(asn:) network failed (\(error)); serving cached")
        return cached
      }
      throw error
    }
  }

  public func documents(filter: FilterState) throws -> Wrapped.Documents {
    try wrapped.documents(filter: filter)
  }

  public func documentIDs(filter: FilterState) async throws -> [UInt] {
    try await wrapped.documentIDs(filter: filter)
  }

  public func reconcileDocumentDeletions() async throws {
    let localIDs = try database.allDocumentIDs(serverID: serverID)
    // Nothing cached yet → nothing to reconcile (skip the id fetch entirely).
    guard !localIDs.isEmpty else { return }

    // The unfiltered list is the complete live id set for the server.
    let serverIDs = Set(try await wrapped.documentIDs(filter: .empty))
    let removed = localIDs.subtracting(serverIDs)
    guard !removed.isEmpty else { return }

    Logger.shared.info(
      "Reconcile: dropping \(removed.count, privacy: .public) remotely-deleted documents")
    try database.deleteDocuments(serverID: serverID, removedIDs: Array(removed))
  }

  public func nextAsn() async throws -> UInt {
    try await wrapped.nextAsn()
  }

  public func metadata(documentId: UInt) async throws -> Metadata {
    try await wrapped.metadata(documentId: documentId)
  }

  public func notes(documentId: UInt) async throws -> [Document.Note] {
    try await wrapped.notes(documentId: documentId)
  }

  public func createNote(documentId: UInt, note: ProtoDocument.Note) async throws
    -> [Document.Note]
  {
    try await wrapped.createNote(documentId: documentId, note: note)
  }

  public func deleteNote(id: UInt, documentId: UInt) async throws -> [Document.Note] {
    try await wrapped.deleteNote(id: id, documentId: documentId)
  }

  public func shareLinks(documentId: UInt) async throws -> [DataModel.ShareLink] {
    try await wrapped.shareLinks(documentId: documentId)
  }

  public func trash() async throws -> [Document] {
    try await wrapped.trash()
  }

  public func restoreTrash(documents: [UInt]) async throws {
    try await wrapped.restoreTrash(documents: documents)
  }

  public func emptyTrash(documents: [UInt]) async throws {
    try await wrapped.emptyTrash(documents: documents)
  }

  public func thumbnail(document: Document) async throws -> Image? {
    try await wrapped.thumbnail(document: document)
  }

  public func thumbnailData(document: Document) async throws -> Data {
    try await wrapped.thumbnailData(document: document)
  }

  public nonisolated func thumbnailRequest(document: Document) throws -> URLRequest {
    try wrapped.thumbnailRequest(document: document)
  }

  public func download(
    document: Document, original: Bool,
    progress: (@Sendable (Double) -> Void)?
  ) async throws -> URL {
    try await wrapped.download(document: document, original: original, progress: progress)
  }

  public func suggestions(documentId: UInt) async throws -> Suggestions {
    try await wrapped.suggestions(documentId: documentId)
  }

  // MARK: - Server / share links / settings (forwarded)

  public func remoteVersion() async throws -> RemoteVersion {
    try await wrapped.remoteVersion()
  }

  public func create(shareLink: ProtoShareLink) async throws -> DataModel.ShareLink {
    try await wrapped.create(shareLink: shareLink)
  }

  public func delete(shareLink: DataModel.ShareLink) async throws {
    try await wrapped.delete(shareLink: shareLink)
  }

  public func update(settings: UISettingsSettings) async throws {
    try await wrapped.update(settings: settings)
    // Write the new settings through to the cached `ui_settings` singleton (the
    // server returns no body), merging onto the cached user/permissions, so the
    // live observation repaints `settings` (e.g. saved-view visibility).
    if let current = try database.uiSettings(serverID: serverID) {
      let merged = UISettings(
        user: current.user, settings: settings, permissions: current.permissions)
      try database.setUISettings(merged, serverID: serverID)
    }
  }

  // MARK: - Tasks (forwarded)

  public func task(id: UInt) async throws -> PaperlessTask? {
    try await wrapped.task(id: id)
  }

  public func tasks(limit: UInt) async throws -> [PaperlessTask] {
    try await wrapped.tasks(limit: limit)
  }

  public func tasks() throws -> Wrapped.Tasks {
    try wrapped.tasks()
  }

  public func acknowledge(tasks: [UInt]) async throws {
    try await wrapped.acknowledge(tasks: tasks)
  }

  // MARK: - Infrastructure pass-throughs

  public nonisolated var delegate: (any URLSessionDelegate)? { wrapped.delegate }

  public func supports(feature: BackendFeature) -> Bool {
    wrapped.supports(feature: feature)
  }
}
