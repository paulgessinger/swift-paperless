//
//  DocumentStore.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.04.23.
//

import Common
import DataModel
import Foundation
import Networking
import Nuke
import Persistence
import Semaphore
import SwiftUI
import os

@MainActor
@Observable
public final class DocumentStore: Sendable {
  // MARK: Observed state

  public private(set) var documents: [UInt: Document] = [:]

  public private(set) var tasks: [PaperlessTask] = []

  /// The live element projection (DB → typed `ValueObservation`). The store owns
  /// it and re-exposes its collections through the computed delegates below, so
  /// `store.tags` etc. keep working and stay reactive (a view reading
  /// `store.tags` tracks `ElementStore.tags` through the getter). The reference
  /// is stable across its lifetime — only its contents change — so it is
  /// `@ObservationIgnored`; the inner `@Observable` does the tracking.
  @ObservationIgnored
  public let elementStore = ElementStore()

  // Element collections and singletons — read-only projections of the DB,
  // observed via `elementStore`. Writes go through the repository (which
  // write-throughs to the DB); the observation repaints these.
  public var correspondents: [UInt: Correspondent] { elementStore.correspondents }
  public var documentTypes: [UInt: DocumentType] { elementStore.documentTypes }
  public var tags: [UInt: Tag] { elementStore.tags }
  public var savedViews: [UInt: SavedView] { elementStore.savedViews }
  public var storagePaths: [UInt: StoragePath] { elementStore.storagePaths }
  public var users: [UInt: User] { elementStore.users }
  public var groups: [UInt: UserGroup] { elementStore.groups }
  public var customFields: [UInt: CustomField] { elementStore.customFields }
  public var currentUser: User? { elementStore.currentUser }
  public var serverConfiguration: ServerConfiguration? { elementStore.serverConfiguration }
  public var permissions: UserPermissions { elementStore.permissions }
  public var settings: UISettingsSettings { elementStore.settings }

  /// True while a network `sync` is in flight. Distinct from data-presence so a
  /// cold cache shows loading rather than emptiness.
  public private(set) var isRefreshing = false

  /// The last automatic (non-user-initiated) sync failure, kept so the UI can
  /// surface a degraded state without tearing down the cached display.
  /// User-initiated syncs rethrow instead (the caller toasts, as before).
  public private(set) var lastSyncError: (any DisplayableError)?

  public var activeTasks: [PaperlessTask] {
    tasks.filter(\.isActive)
  }

  // MARK: Members

  public enum Event: Sendable {
    case deleted(document: Document)
    case changed(document: Document)
    case changeReceived(document: Document)

    case repositoryWillChange
    case repositoryChanged
    case taskError(task: PaperlessTask)
  }

  public let events = Broadcaster<Event>()

  public let semaphore = AsyncSemaphore(value: 1)

  public private(set) var repository: any Repository

  public private(set) var imagePipeline: ImagePipeline

  @ObservationIgnored
  private nonisolated(unsafe) var taskUpdateTask: Task<Void, Never>?

  // MARK: Methods

  public init(repository: some Repository) {
    self.repository = repository
    self.imagePipeline = Self.makeImagePipeline(delegate: repository.delegate)
    wireElementStore()
  }

  deinit {
    taskUpdateTask?.cancel()
  }

  /// Point the element projection at the active repository's DB. Under the
  /// source-of-truth model every production/preview repository fronts a DB
  /// (`CachingBackend`); a repository that doesn't (e.g. `NullRepository` before
  /// login) detaches the projection.
  private func wireElementStore() {
    if let backend = repository as? any CachingBackend {
      elementStore.repoint(database: backend.database, serverID: backend.serverID)
    } else {
      elementStore.reset()
    }
  }

  @Sendable
  private func taskPoller() async {
    Logger.shared.debug("Task poller initialize")
    repeat {
      guard !Task.isCancelled else { break }
      Logger.shared.debug("Polling tasks")

      let currentActiveTasks = Set(tasks.filter(\.isActive).map(\.id))
      Logger.shared.debug("Current active: \(currentActiveTasks)")
      await fetchTasks()
      let newErrors: [PaperlessTask] = tasks.filter {
        $0.status == .FAILURE && currentActiveTasks.contains($0.id)
      }
      Logger.shared.debug("New errors: \(newErrors)")

      if !newErrors.isEmpty {
        Task {
          // don't send the errors all at once if there's multiple
          for task in newErrors {
            events.emit(.taskError(task: task))
            try? await Task.sleep(for: .seconds(2))
          }
        }
      }

      let emptyDuration = 60.0
      let activeDuration: Double =
        ProcessInfo.processInfo.environment["TASK_POLLING_INTERVAL"].flatMap { Double($0) } ?? 2.5

      let duration: Duration = .seconds(activeTasks.isEmpty ? emptyDuration : activeDuration)
      Logger.shared.debug("Task poller sleeping for \(duration)")
      try? await Task.sleep(for: duration)
    } while !Task.isCancelled
    Logger.shared.debug("Task poller terminating")
  }

  public func startTaskPolling() {
    taskUpdateTask?.cancel()
    taskUpdateTask = Task(operation: taskPoller)
  }

  public func clearDocuments() {
    documents = [:]
  }

  public func clear() {
    documents = [:]
    tasks = []
    lastSyncError = nil
    // The element projection is owned by `elementStore` and (re)wired by
    // `wireElementStore()` on repository change — nothing to clear here.
  }

  public func set(repository: some Repository, reload: Bool = true) {
    self.repository = repository
    imagePipeline = Self.makeImagePipeline(delegate: repository.delegate)
    wireElementStore()
    if reload {
      events.emit(.repositoryChanged)
      clear()
    }
  }

  private static func makeImagePipeline(delegate: (any URLSessionDelegate)?) -> ImagePipeline {
    let dataLoader = DataLoader()
    if let delegate {
      dataLoader.delegate = delegate
    }
    var config = ImagePipeline.Configuration(dataLoader: dataLoader)
    if let cacheURL = sharedThumbnailCacheURL(),
      let dataCache = try? DataCache(path: cacheURL)
    {
      config.dataCache = dataCache
    }
    return ImagePipeline(configuration: config)
  }

  private static func sharedThumbnailCacheURL() -> URL? {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: ContentStore.appGroup)
    else { return nil }
    let url = container.appendingPathComponent("Caches/Nuke", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path)
    return url
  }

  public func preloadThumbnail(for document: Document) {
    guard let urlRequest = try? repository.thumbnailRequest(document: document) else { return }
    imagePipeline.loadImage(with: ImageRequest(urlRequest: urlRequest, priority: .high)) { _ in }
  }

  public func updateDocument(_ document: Document) async throws -> Document {
    Logger.shared.info("Updating document with ID \(document.id, privacy: .public)")
    try checkPermission(.change, for: .document)
    events.emit(.changed(document: document))

    var document = document

    if settings.documentEditing.removeInboxTags {
      Logger.shared.debug("Removing inbox tags from document as per setting")
      let inboxTags = tags.values.filter(\.isInboxTag)
      for tag in inboxTags {
        document.tags.removeAll(where: { $0 == tag.id })
      }
    }

    let updated = try await repository.update(document: document)
    documents[updated.id] = updated
    events.emit(.changeReceived(document: updated))
    return updated
  }

  public func deleteDocument(_ document: Document) async throws {
    Logger.shared.info("Deleting document with ID \(document.id, privacy: .public)")
    try checkPermission(.delete, for: .document)
    try await repository.delete(document: document)
    documents.removeValue(forKey: document.id)
    events.emit(.deleted(document: document))
  }

  public func deleteNote(from document: Document, id: UInt) async throws {
    Logger.shared.info("Deleting note with ID \(id, privacy: .public)")
    try checkPermission(.delete, for: .note)
    events.emit(.changed(document: document))
    _ = try await repository.deleteNote(id: id, documentId: document.id)

    events.emit(.changeReceived(document: document))
  }

  public func addNote(to document: Document, note: ProtoDocument.Note) async throws {
    Logger.shared.info("Adding note to document \(document.id, privacy: .public)")
    try checkPermission(.add, for: .note)
    events.emit(.changed(document: document))

    _ = try await repository.createNote(documentId: document.id, note: note)

    events.emit(.changeReceived(document: document))
  }

  public func notes(for document: Document) async throws -> [Document.Note] {
    try checkPermission(.view, for: .note)
    return try await repository.notes(documentId: document.id)
  }

  // Polling fetches a small leading page to bound decode cost when a server
  // has many unacknowledged tasks. Active and recently-failed tasks are at
  // the top of the list (sorted by creation date), so this window catches
  // everything the poller actually consumes (badge count, error events).
  public static let taskPollLimit: UInt = 100

  public func fetchTasks() async {
    guard (try? checkPermission(.view, for: .paperlessTask)) != nil else {
      return
    }
    guard let tasks = try? await repository.tasks(limit: Self.taskPollLimit) else {
      return
    }
    self.tasks = tasks
  }

  public func acknowledge(tasks ids: [UInt]) async throws {
    try await repository.acknowledge(tasks: ids)
    await fetchTasks()
  }

  // On-demand element refreshers kept for their external callers. Under the
  // source-of-truth model "refresh collection X" means "sync into the DB"; the
  // live observation then repaints the projection. `syncElements` reconciles
  // every collection at once, so these all delegate to it.
  public func fetchAllUsers() async throws { try await sync(userInitiated: true) }
  public func fetchAllGroups() async throws { try await sync(userInitiated: true) }
  public func fetchAllCustomFields() async throws { try await sync(userInitiated: true) }

  /// Refresh `ui_settings` (permissions/settings) from the network. Syncs into
  /// the DB, then synchronously pulls the singleton into the projection — the
  /// one path (`DocumentListViewModel.load`) that reads `permissions`
  /// immediately afterwards can't wait for the observation's runloop hop.
  public func fetchUISettings() async throws {
    try await sync(userInitiated: true)
    if let backend = repository as? any CachingBackend {
      elementStore.refreshUISettings(from: backend.database, serverID: backend.serverID)
    }
  }

  /// Network → DB via the caching backend; the live element observation repaints
  /// the projection. Automatic syncs fail soft into `lastSyncError`;
  /// user-initiated syncs rethrow so the caller can surface the failure (toast).
  public func sync(userInitiated: Bool = false) async throws {
    Logger.shared.notice("Sync store (userInitiated: \(userInitiated))")
    guard let backend = repository as? any CachingBackend else {
      // No DB-backed repository (e.g. NullRepository before login). Nothing to
      // sync; the projection is empty until a caching repository is set.
      Logger.shared.info("Sync skipped: repository is not a caching backend")
      return
    }
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      try await backend.syncElements()
      lastSyncError = nil
      Logger.shared.info("Sync store complete")
    } catch {
      if userInitiated { throw error }
      if !error.isCancellationError {
        lastSyncError = error as? any DisplayableError
        Logger.shared.error("Background sync failed (suppressed): \(error)")
      }
    }
  }

  /// The eager entry views call. Triggers a network → DB sync; the element
  /// projection repaints from the live observation.
  public func fetchAll() async throws {
    Logger.shared.notice("Fetch all store request")
    try await sync()
  }

  public func document(id: UInt) async throws -> Document? {
    try checkPermission(.view, for: .document)
    return try await repository.document(id: id)
  }

  private func create<E, R>(
    _: R.Type, from element: E,
    method: (E) async throws -> R
  ) async throws -> R
  where E: Sendable & PermissionsModel, R: Identifiable & Sendable {
    // `settings` is kept live by the element observation, so its permission
    // defaults are already current — apply them directly. The repository
    // write-throughs the created element to the DB; the observation repaints it
    // into the projection.
    let updated = settings.permissions.appliedAsDefaults(to: element)
    return try await method(updated)
  }

  private func update<E>(
    _ element: E,
    method: (E) async throws -> E
  ) async throws where E: Identifiable & Sendable {
    _ = try await method(element)
  }

  private func delete<E>(
    _ element: E,
    method: (E) async throws -> Void
  ) async throws where E: Identifiable & Sendable {
    do {
      try await method(element)
    } catch let RequestError.unexpectedStatusCode(code: code, _) where code == .notFound {
      let id = "\(element.id)"
      Logger.api.debug(
        "Element with ID \(id) not found (probably already deleted)")
    }
    // The repository write-throughs the delete to the DB; the observation
    // removes it from the projection.
  }

  public func create(tag: ProtoTag) async throws -> Tag {
    Logger.api.info("Creating tag with name \(tag.name)")
    return try await create(
      Tag.self,
      from: tag,
      method: repository.create(tag:))
  }

  public func update(tag: Tag) async throws {
    Logger.api.info("Updating tag with ID \(tag.id)")
    return try await update(tag, method: repository.update(tag:))
  }

  public func delete(tag: Tag) async throws {
    Logger.api.info("Deleting tag with ID \(tag.id)")
    return try await delete(tag, method: repository.delete(tag:))
  }

  public func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
    Logger.api.info("Creating correspondent with name \(correspondent.name)")
    return try await create(
      Correspondent.self,
      from: correspondent,
      method: repository.create(correspondent:))
  }

  public func update(correspondent: Correspondent) async throws {
    Logger.api.info("Updating correspondent with ID \(correspondent.id)")
    return try await update(
      correspondent,
      method: repository.update(correspondent:))
  }

  public func delete(correspondent: Correspondent) async throws {
    Logger.api.info("Deleting correspondent with ID \(correspondent.id)")
    return try await delete(
      correspondent,
      method: repository.delete(correspondent:))
  }

  public func create(documentType: ProtoDocumentType) async throws -> DocumentType {
    Logger.api.info("Creating document type with name \(documentType.name)")
    return try await create(
      DocumentType.self,
      from: documentType,
      method: repository.create(documentType:))
  }

  public func update(documentType: DocumentType) async throws {
    Logger.api.info("Updating document type with ID \(documentType.id)")
    return try await update(
      documentType,
      method: repository.update(documentType:))
  }

  public func delete(documentType: DocumentType) async throws {
    Logger.api.info("Deleting document type with ID \(documentType.id)")
    return try await delete(
      documentType,
      method: repository.delete(documentType:))
  }

  public func create(savedView: ProtoSavedView) async throws -> SavedView {
    Logger.api.info("Creating saved view with name \(savedView.name)")
    let created = try await repository.create(savedView: savedView)

    try await handleSavedViewVisibility(created)

    return created
  }

  private func handleSavedViewVisibility(_ savedView: SavedView) async throws {

    guard repository.supports(feature: .savedViewNewVisibility) else {
      // Nothing to do
      return
    }

    Logger.api.info("Updating saved view visibility via ui settings")

    // `settings` is a read-only projection; mutate a local copy and write it
    // through the repository (which updates the cached singleton → observation
    // repaints `settings`).
    var newSettings = settings

    // Normalize to exclude
    var dashboardVisibleIds = newSettings.savedViews.dashboardViewsVisibleIds.filter {
      $0 != savedView.id
    }
    var sidebarVisibleIds = newSettings.savedViews.sidebarViewsVisibleIds.filter {
      $0 != savedView.id
    }

    if savedView.showOnDashboard {
      dashboardVisibleIds.append(savedView.id)
    }

    if savedView.showInSidebar {
      sidebarVisibleIds.append(savedView.id)
    }

    newSettings.savedViews.dashboardViewsVisibleIds = dashboardVisibleIds
    newSettings.savedViews.sidebarViewsVisibleIds = sidebarVisibleIds

    try await repository.update(settings: newSettings)
  }

  public func create(document: ProtoDocument, file: URL, filename: String? = nil) async throws {
    Logger.api.info("Creating document with name \(document.title)")
    _ = try await repository.create(
      document: document, file: file, filename: filename ?? file.lastPathComponent)
    startTaskPolling()
  }

  public func update(savedView: SavedView) async throws {
    Logger.api.info("Updating saved view with ID \(savedView.id)")
    _ = try await repository.update(savedView: savedView)

    try await handleSavedViewVisibility(savedView)
  }

  public func delete(savedView: SavedView) async throws {
    Logger.api.info("Deleting saved view with ID \(savedView.id)")
    try await repository.delete(savedView: savedView)
  }

  public func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
    Logger.api.info("Creating storage path with name \(storagePath.name)")
    return try await create(
      StoragePath.self,
      from: storagePath,
      method: repository.create(storagePath:))
  }

  public func update(storagePath: StoragePath) async throws {
    Logger.api.info("Updating storage path with ID \(storagePath.id)")
    try await update(
      storagePath,
      method: repository.update(storagePath:))
  }

  public func delete(storagePath: StoragePath) async throws {
    Logger.api.info("Deleting storage path with ID \(storagePath.id)")
    try await delete(
      storagePath,
      method: repository.delete(storagePath:))
  }

  private func checkPermission(
    _ operation: UserPermissions.Operation, for resource: UserPermissions.Resource
  ) throws {
    Logger.api.info(
      "Checking permission for \(operation.description, privacy: .public) on \(resource.rawValue, privacy: .public)"
    )
    if !permissions.test(operation, for: resource) {
      Logger.api.debug("No permissions for \(operation.description) on \(resource.rawValue)")
      throw PermissionsError(resource: resource, operation: operation)
    }
  }
}

//// Permissions checking for resources
extension DocumentStore {
  public func userCanView(document: Document) -> Bool {
    if !permissions.test(.view, for: .document) {
      return false
    }

    return currentUser?.canView(document) ?? false
  }

  public func userCanChange(document: Document) -> Bool {
    if !permissions.test(.change, for: .document) {
      return false
    }

    return currentUser?.canChange(document) ?? false
  }

  public func userCanDelete(document: Document) -> Bool {
    if !permissions.test(.delete, for: .document) {
      return false
    }

    return currentUser?.canDelete(document) ?? false
  }

  /// All ancestor tag ids of `id` (excluding `id` itself), walking up the
  /// `parent` chain. Stops at unknown ids and at cycles. Used to mirror the
  /// backend behavior of implicitly attaching ancestors when a child tag is
  /// added to a document.
  public func tagAncestors(of id: UInt) -> [UInt] {
    var result: [UInt] = []
    var seen: Set<UInt> = [id]
    var current = tags[id]?.parent
    while let parent = current, !seen.contains(parent), let tag = tags[parent] {
      result.append(parent)
      seen.insert(parent)
      current = tag.parent
    }
    return result
  }

  /// All descendant tag ids of `id` (excluding `id` itself). Used to mirror
  /// the backend behavior of removing children when their parent is detached.
  public func tagDescendants(of id: UInt) -> Set<UInt> {
    var descendants: Set<UInt> = []
    var frontier: Set<UInt> = [id]
    while !frontier.isEmpty {
      var next: Set<UInt> = []
      for tag in tags.values {
        guard let parent = tag.parent, frontier.contains(parent) else { continue }
        if descendants.insert(tag.id).inserted, tag.id != id {
          next.insert(tag.id)
        }
      }
      frontier = next
    }
    return descendants
  }
}
