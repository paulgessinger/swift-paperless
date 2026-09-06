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

  public private(set) var tasks: [PaperlessTask] = []

  /// The live projection of the *active* server (DB → typed `ValueObservation`),
  /// or `nil` when there is no server to project (before login, or a repository
  /// that fronts no DB). The store owns it and re-exposes it through the
  /// read-only computed delegates below, so `store.tags` etc. keep working.
  ///
  /// Deliberately a tracked stored property, and deliberately *replaced* rather
  /// than re-pointed on a connection switch. Both hops a delegate walks —
  /// `projection`, then the value on it — are observation-tracked, so views
  /// repaint when the instance is swapped as well as when its contents change.
  /// Replacing it is also what makes a superseded server's late emission
  /// harmless: that server's loops hold the object they were born with, and
  /// once it is no longer this property nothing reads what they write into it.
  public private(set) var projection: ServerProjection?

  // Element collections and singletons — read-only projections of the DB,
  // observed via `projection`. Writes go through the repository (which
  // write-throughs to the DB); the observation repaints these. The fallbacks are
  // the serverless state: the same empties a fresh projection is born with.
  public var correspondents: [UInt: Correspondent] { projection?.correspondents ?? [:] }
  public var documentTypes: [UInt: DocumentType] { projection?.documentTypes ?? [:] }
  public var tags: [UInt: Tag] { projection?.tags ?? [:] }
  public var savedViews: [UInt: SavedView] { projection?.savedViews ?? [:] }
  public var storagePaths: [UInt: StoragePath] { projection?.storagePaths ?? [:] }
  public var users: [UInt: User] { projection?.users ?? [:] }
  public var groups: [UInt: UserGroup] { projection?.groups ?? [:] }
  public var customFields: [UInt: CustomField] { projection?.customFields ?? [:] }
  public var currentUser: User? { projection?.currentUser }
  public var serverConfiguration: ServerConfiguration? { projection?.serverConfiguration }
  /// The permission matrix to *gate on* — and, until `ui_settings` has landed
  /// for the active server, a deliberate optimistic lie.
  ///
  /// The stored value starts `.empty`, which tests `false` for everything and is
  /// therefore indistinguishable from a genuine denial: on a cold start (first
  /// launch, or any launch while offline before the first successful sync) every
  /// gate in the app read as "you have no permissions". Handing out `.full`
  /// instead means the UI stays usable and the *server* answers, which is the
  /// same bet `CachingRepository.syncElements` already makes (its gate is a
  /// `UserPermissions?`, and `nil` → fetch everything, let the 403 decide).
  ///
  /// Anything that *displays* this matrix, rather than gating on it, must check
  /// ``permissionsKnown`` first — otherwise it reports access the server never
  /// granted. `PermissionsView` does.
  public var permissions: UserPermissions {
    guard let projection, projection.isHydrated else { return .full }
    return projection.permissions
  }

  public var settings: UISettingsSettings { projection?.settings ?? UISettingsSettings() }

  /// Whether ``permissions`` reflects the server's answer yet, or is the
  /// optimistic `.full` stand-in. Gates don't need this; anything that shows the
  /// matrix, or that would otherwise assert *why* something is unavailable,
  /// does.
  public var permissionsKnown: Bool { projection?.isHydrated ?? false }

  /// The last automatic (non-user-initiated) sync failure, kept so the UI can
  /// surface a degraded state without tearing down the cached display.
  /// User-initiated syncs rethrow instead (the caller toasts, as before).
  public private(set) var lastSyncError: (any DisplayableError)?

  /// Every sync stage running right now on the active server, in a fixed order;
  /// empty when idle. Drives the stage rows and progress bars on the Offline &
  /// Sync screen.
  ///
  /// Owned by the session, so this is a plain projection: the screen now repaints
  /// for work the *scheduler* started on this server too, which it could not do
  /// while the only reporter was this store.
  public var syncActivities: [SyncActivity] { session?.syncActivities ?? [] }

  /// Whether the active server has any sync work in flight. Distinct from
  /// ``syncActivities`` being non-empty, which only says whether a stage is
  /// currently *reporting* — see ``ServerSession/isSyncing``.
  public var isSyncing: Bool { session?.isSyncing ?? false }

  /// When the document reconcile sweep (R2/R3δ/membership) last **succeeded**.
  /// `nil` until the first successful reconcile this session.
  ///
  /// Owned by the session, not mirrored into stored state here: the session's
  /// own stamp is observed, so a view reading this through the store still
  /// repaints when a sweep lands — including a sweep the *scheduler* ran, which
  /// the store used never to hear about.
  public var lastReconcileAt: Date? { session?.lastReconcileSuccess }

  /// When the active server's library was last fully filled (`nil` if never),
  /// observed from `server_sync_state.library_coverage_at` so the Offline & Sync
  /// screen tracks fills *and* a cache wipe (which clears it) instead of staying
  /// on "Never".
  ///
  /// The one that made this bug visible: it may not emit again for hours, so a
  /// value the previous server's observation slipped in after a switch used to
  /// stay on screen until the next fill.
  public var libraryCoverageAt: Date? { projection?.libraryCoverageAt }

  /// Views (saved or default) whose proactive offline fill the server most
  /// recently rejected — observed from `query_sync_error` for the active server
  /// so the Offline & Sync screen can warn that they aren't fully cached.
  public var syncErrors: [QuerySyncError] { projection?.syncErrors ?? [] }

  /// Live count of `document` rows cached for the active server — lets the
  /// Offline & Sync screen show the effect of the proactive fill and the
  /// downgrade GC (switching *Entire library* → *Recently browsed*) without a
  /// debugger.
  public var cachedDocumentCount: Int { projection?.cachedDocumentCount ?? 0 }

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

  /// The registry this store activates through, or `nil` for a fixture store
  /// pinned to one session. Holding the registry — rather than a `Database` and
  /// a `ConnectionManager` to assemble stacks from — is what stops the store
  /// becoming a *second* owner of a server the registry already drives.
  @ObservationIgnored
  private let registry: ServerSessionRegistry?

  /// The session driving this store, or `nil` before login.
  ///
  /// Deliberately *not* `@ObservationIgnored`: ``repository`` is computed from
  /// it, so every view that read the outgoing server's repository has to be
  /// invalidated when this changes.
  private var session: ServerSession?

  /// Stands in for "no active server". Held rather than constructed per access
  /// so ``repository`` keeps a stable identity while the store is serverless.
  @ObservationIgnored
  private let nullRepository = NullRepository()

  /// The active server's repository, owned by its ``ServerSession`` rather than
  /// by this store. Before login there is no session, and this reads as
  /// `NullRepository` — which detaches the element projection, exactly as it
  /// always has.
  public var repository: any Repository { session?.repository ?? nullRepository }

  public private(set) var imagePipeline: ImagePipeline

  @ObservationIgnored
  private var taskUpdateTask: Task<Void, Never>?

  // MARK: Methods

  /// The production store: it activates onto servers by asking `registry` for
  /// their sessions, so neither the app nor the extension can end up driving a
  /// server the registry already owns.
  public convenience init(registry: ServerSessionRegistry) {
    self.init(registry: registry, session: nil)
  }

  /// A store pinned to one session, for previews and tests. It cannot activate
  /// onto another server — there is no registry to ask — which is the right
  /// shape for a fixture.
  public convenience init(session: ServerSession) {
    self.init(registry: nil, session: session)
  }

  private init(registry: ServerSessionRegistry?, session: ServerSession?) {
    self.registry = registry
    self.session = session
    imagePipeline = Self.makeImagePipeline(delegate: session?.repository?.delegate)
    rebuildProjection()
  }

  deinit {
    taskUpdateTask?.cancel()
  }

  /// Build a projection for the active server, replacing whatever was there.
  ///
  /// Under the source-of-truth model every production/preview repository fronts
  /// a DB (`CachingBackend`); a repository that doesn't (e.g. `NullRepository`
  /// before login) leaves the store serverless and the delegates on their empty
  /// defaults.
  ///
  /// Replacement, not re-pointing, is the whole design: the outgoing server's
  /// observation loops die with the object they wrote into (they hold it weakly,
  /// so dropping it here runs its `deinit` and cancels them), and a value one of
  /// them had already produced can no longer reach the store — cancellation is
  /// cooperative, so it *would* still be delivered, it just lands somewhere
  /// nothing reads.
  private func rebuildProjection() {
    guard let backend = session?.backend else {
      projection = nil
      return
    }
    projection = ServerProjection(database: backend.database, serverID: backend.serverID)
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

  /// Drop the per-server state this store still holds in memory, on a repository
  /// swap. That is only the task list and the last sync error now: documents
  /// aren't held in memory under source-of-truth (the list observes the DB
  /// directly), and the element projection is owned by `projection` and
  /// rebuilt by `rebuildProjection()`. `private` because `install(session:)` is
  /// the one caller — a swap is the only moment this is the right thing to do.
  private func clear() {
    tasks = []
    lastSyncError = nil
  }

  /// Point the store at `connection` — the only supported way to put it on a server.
  ///
  /// The stack is assembled by the server's ``ServerSession``, so a caller cannot
  /// hand the store a bare uncached repository. That mistake detaches the element
  /// projection and blanks every element read site until the next relaunch, and it
  /// shipped once already from `ConnectionsView.updateExtraHeaders`; routing every
  /// activation through the session that owns the server is what makes it
  /// unrepresentable rather than merely discouraged — and is also what stops two
  /// owners driving the same server at once.
  public func activate(
    connection: StoredConnection,
    reload: Bool = true
  ) async throws {
    guard let registry else {
      preconditionFailure("activate(connection:) called on a store built without a registry")
    }
    let session = registry.session(for: connection.id)
    // Build before installing, not lazily on first use: `repository` reads
    // straight off the session, and a store published on a session that has not
    // assembled its stack yet would render one pass against `NullRepository`.
    try await session.prepareRepository(for: connection)
    install(session: session, reload: reload)
  }

  /// The single chokepoint for swapping the live repository. Private on purpose:
  /// see ``activate(connection:database:manager:mode:reload:)``. Any future path
  /// that needs to swap repositories should route through here so the invariant
  /// below keeps covering it.
  private func install(session: ServerSession, reload: Bool) {
    // Nothing is cancelled here any more, and that is the point.
    //
    // The store used to cancel the in-flight element sync and library fill on
    // every swap, because it owned them: they wrote the *outgoing* server's rows
    // and a follow-up `sync()` would join them and return without ever fetching
    // the new server's cache. Now that work belongs to the outgoing *session* —
    // it is simply an inactive server's work, keyed to that server, and there is
    // no way for the incoming server's sync to join it. So it keeps running, and
    // switching servers mid-fill no longer throws away the pages already paid
    // for.
    //
    // Progress needs no unwiring either: each session publishes its own stages,
    // so pointing the store at a new one *is* switching which server's progress
    // the Offline & Sync screen shows.
    self.session = session
    imagePipeline = Self.makeImagePipeline(delegate: session.repository?.delegate)
    rebuildProjection()
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
    return try await performing(.change, on: .document) {
      events.emit(.changed(document: document))

      var document = document

      if settings.documentEditing.removeInboxTags {
        Logger.shared.debug("Removing inbox tags from document as per setting")
        let inboxTags = tags.values.filter(\.isInboxTag)
        for tag in inboxTags {
          document.tags.removeAll(where: { $0 == tag.id })
        }
      }

      // The repository write-throughs the confirmed value to the DB; the list/detail
      // observations repaint it in place (no in-memory dict to update).
      let updated = try await repository.update(document: document)
      events.emit(.changeReceived(document: updated))
      return updated
    }
  }

  public func deleteDocument(_ document: Document) async throws {
    Logger.shared.info("Deleting document with ID \(document.id, privacy: .public)")
    try await performing(.delete, on: .document) {
      // The repository write-throughs the delete to the DB, explicitly pruning
      // every cached query_order referencing it (no FK cascade does this — see
      // CachingRepository.delete(document:)), and the observations repaint.
      try await repository.delete(document: document)
      events.emit(.deleted(document: document))
    }
  }

  public func deleteNote(from document: Document, id: UInt) async throws {
    Logger.shared.info("Deleting note with ID \(id, privacy: .public)")
    try await performing(.delete, on: .note) {
      events.emit(.changed(document: document))
      _ = try await repository.deleteNote(id: id, documentId: document.id)

      events.emit(.changeReceived(document: document))
    }
  }

  public func addNote(to document: Document, note: ProtoDocument.Note) async throws {
    Logger.shared.info("Adding note to document \(document.id, privacy: .public)")
    try await performing(.add, on: .note) {
      events.emit(.changed(document: document))

      _ = try await repository.createNote(documentId: document.id, note: note)

      events.emit(.changeReceived(document: document))
    }
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
    // The poller is not restarted on a connection switch, and the fetch below is
    // a suspension point, so the session has to be re-checked: the outgoing
    // server's task list must not land in the store after `install` cleared it
    // for the incoming one.
    let session = session
    guard let tasks = try? await repository.tasks(limit: Self.taskPollLimit) else {
      return
    }
    guard self.session === session else {
      Logger.shared.debug("Dropping task list from a superseded server")
      return
    }
    self.tasks = tasks
  }

  public func acknowledge(tasks ids: [UInt]) async throws {
    try await repository.acknowledge(tasks: ids)
    await fetchTasks()
  }

  /// Refresh `ui_settings` (permissions/settings) from the network, then pull
  /// the singleton into the projection before returning — the one path
  /// (`DocumentListViewModel.load`) that reads `permissions` immediately
  /// afterwards can't wait for the observation's runloop hop. Automatic (not
  /// user-initiated): a sync failure fails soft and we proceed with the cached
  /// permissions (offline-first) instead of aborting the launch load.
  public func fetchUISettings() async throws {
    try await sync()
    // Re-read after the await: a switch during the sync means the projection to
    // refresh is the new server's, and it reads its own database and serverID.
    await projection?.refreshUISettings()
  }

  /// Network → DB via the caching backend; the live element observation repaints
  /// the projection. Concurrent calls coalesce onto a single in-flight
  /// `syncElements` (the session's `elementSyncTask`); each caller still applies its own
  /// `userInitiated` policy to the shared outcome — automatic syncs fail soft
  /// into `lastSyncError`, user-initiated syncs rethrow so the caller can
  /// surface the failure (toast). So a user-initiated call joining a background
  /// sync still sees the error. This is what entry views call eagerly on
  /// appear, and what pull-to-refresh calls with `userInitiated: true`.
  public func sync(userInitiated: Bool = false) async throws {
    Logger.sync.notice("Sync store (userInitiated: \(userInitiated))")
    // Pinned for the whole call, not re-read after the await. A server switch
    // during the element sync would otherwise sync one server's elements and
    // then reconcile a *different* server — harmless (each session owns its own
    // repository, and the outgoing one's work is meant to run on) but
    // incoherent, and a pull-to-refresh on A would force-reconcile B.
    guard let session else { return }
    do {
      try await session.syncElements()
      // `lastSyncError` describes the server this call synced, so an outcome
      // that arrives after a switch must not be shown for — or cleared on — the
      // server now on screen.
      if self.session === session { lastSyncError = nil }
      Logger.sync.info("Sync store complete")
      // Kick the reconcile alongside the element sync (throttled,
      // non-blocking). Not just remote deletes, despite the name it used to
      // carry: it is all three sweeps — deletions, the changed-metadata delta,
      // then the saved-view membership rebuild. Pull-to-refresh
      // (userInitiated) bypasses the throttle.
      let userInitiated = userInitiated
      Task { await session.reconcileDocuments(force: userInitiated) }
    } catch {
      // A cancellation is never the user's problem to see: the caller's own task
      // went away. (A connection switch no longer retires it — that sync belongs
      // to the outgoing session and runs on.) Drop it before the userInitiated
      // rethrow so it doesn't toast.
      if error.isCancellationError {
        Logger.sync.debug("Element sync cancelled")
        return
      }
      if userInitiated { throw error }
      // Only presentable failures are recorded. A non-displayable one (a GRDB
      // `DatabaseError`, a raw `URLError`) leaves any degraded state already
      // on screen intact rather than clearing it.
      if let displayable = error as? any DisplayableError, self.session === session {
        lastSyncError = displayable
      }
      Logger.sync.error("Background sync failed (suppressed): \(error)")
    }
  }

  public func document(id: UInt) async throws -> Document? {
    try checkPermission(.view, for: .document)
    return try await repository.document(id: id)
  }

  private func create<E, R>(
    _: R.Type, from element: E,
    resource: UserPermissions.Resource,
    method: (E) async throws -> R
  ) async throws -> R
  where E: Sendable & PermissionsModel, R: Identifiable & Sendable {
    try await performing(.add, on: resource) {
      // `settings` is kept live by the element observation, so its permission
      // defaults are already current — apply them directly. The repository
      // write-throughs the created element to the DB; the observation repaints
      // it into the projection.
      let updated = settings.permissions.appliedAsDefaults(to: element)
      return try await method(updated)
    }
  }

  private func update<E>(
    _ element: E,
    resource: UserPermissions.Resource,
    method: (E) async throws -> E
  ) async throws where E: Identifiable & Sendable {
    try await performing(.change, on: resource) {
      _ = try await method(element)
    }
  }

  private func delete<E>(
    _ element: E,
    resource: UserPermissions.Resource,
    method: (E) async throws -> Void
  ) async throws where E: Identifiable & Sendable {
    try await performing(.delete, on: resource) {
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
  }

  public func create(tag: ProtoTag) async throws -> Tag {
    Logger.api.info("Creating tag with name \(tag.name)")
    return try await create(
      Tag.self,
      from: tag,
      resource: .tag,
      method: repository.create(tag:))
  }

  public func update(tag: Tag) async throws {
    Logger.api.info("Updating tag with ID \(tag.id)")
    return try await update(tag, resource: .tag, method: repository.update(tag:))
  }

  public func delete(tag: Tag) async throws {
    Logger.api.info("Deleting tag with ID \(tag.id)")
    return try await delete(tag, resource: .tag, method: repository.delete(tag:))
  }

  public func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
    Logger.api.info("Creating correspondent with name \(correspondent.name)")
    return try await create(
      Correspondent.self,
      from: correspondent,
      resource: .correspondent,
      method: repository.create(correspondent:))
  }

  public func update(correspondent: Correspondent) async throws {
    Logger.api.info("Updating correspondent with ID \(correspondent.id)")
    return try await update(
      correspondent,
      resource: .correspondent,
      method: repository.update(correspondent:))
  }

  public func delete(correspondent: Correspondent) async throws {
    Logger.api.info("Deleting correspondent with ID \(correspondent.id)")
    return try await delete(
      correspondent,
      resource: .correspondent,
      method: repository.delete(correspondent:))
  }

  public func create(documentType: ProtoDocumentType) async throws -> DocumentType {
    Logger.api.info("Creating document type with name \(documentType.name)")
    return try await create(
      DocumentType.self,
      from: documentType,
      resource: .documentType,
      method: repository.create(documentType:))
  }

  public func update(documentType: DocumentType) async throws {
    Logger.api.info("Updating document type with ID \(documentType.id)")
    return try await update(
      documentType,
      resource: .documentType,
      method: repository.update(documentType:))
  }

  public func delete(documentType: DocumentType) async throws {
    Logger.api.info("Deleting document type with ID \(documentType.id)")
    return try await delete(
      documentType,
      resource: .documentType,
      method: repository.delete(documentType:))
  }

  public func create(savedView: ProtoSavedView) async throws -> SavedView {
    Logger.api.info("Creating saved view with name \(savedView.name)")
    try checkPermission(.add, for: .savedView)
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
    try checkPermission(.change, for: .savedView)
    _ = try await repository.update(savedView: savedView)

    try await handleSavedViewVisibility(savedView)
  }

  public func delete(savedView: SavedView) async throws {
    Logger.api.info("Deleting saved view with ID \(savedView.id)")
    try checkPermission(.delete, for: .savedView)
    try await repository.delete(savedView: savedView)
  }

  public func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
    Logger.api.info("Creating storage path with name \(storagePath.name)")
    return try await create(
      StoragePath.self,
      from: storagePath,
      resource: .storagePath,
      method: repository.create(storagePath:))
  }

  public func update(storagePath: StoragePath) async throws {
    Logger.api.info("Updating storage path with ID \(storagePath.id)")
    try await update(
      storagePath,
      resource: .storagePath,
      method: repository.update(storagePath:))
  }

  public func delete(storagePath: StoragePath) async throws {
    Logger.api.info("Deleting storage path with ID \(storagePath.id)")
    try await delete(
      storagePath,
      resource: .storagePath,
      method: repository.delete(storagePath:))
  }

  /// Runs `body` behind its permission check and gives whatever comes back the
  /// operation context the user needs. The local permission matrix and the
  /// server can disagree (object-level permissions aren't in the matrix, and it
  /// can be stale), so a refusal arrives either as our own check failing or as a
  /// 403 from the request — both surface as a `PermissionsError` that names the
  /// operation that was attempted rather than a bare "request was denied".
  private func performing<T>(
    _ operation: UserPermissions.Operation, on resource: UserPermissions.Resource,
    _ body: () async throws -> T
  ) async throws -> T {
    try checkPermission(operation, for: resource)
    do {
      return try await body()
    } catch let RequestError.forbidden(detail) {
      Logger.api.debug(
        "Server refused \(operation.description, privacy: .public) on \(resource.rawValue, privacy: .public)"
      )
      throw PermissionsError(resource: resource, operation: operation, detail: detail)
    }
  }

  private func checkPermission(
    _ operation: UserPermissions.Operation, for resource: UserPermissions.Resource
  ) throws {
    Logger.api.info(
      "Checking permission for \(operation.description, privacy: .public) on \(resource.rawValue, privacy: .public)"
    )
    // No hydration check needed: `permissions` is `.full` until the real matrix
    // lands, so a cold start falls through to the request and lets the server
    // answer instead of refusing with a permission error the user can do
    // nothing about.
    if !permissions.test(operation, for: resource) {
      Logger.api.debug("No permissions for \(operation.description) on \(resource.rawValue)")
      throw PermissionsError(resource: resource, operation: operation)
    }
  }
}

// MARK: - Document cache surface

/// The GRDB-free surface the document list and detail views reach for. Each
/// method resolves the active `CachingBackend` (the production/preview stack) and
/// forwards to its `(database, serverID)`; without a caching backend (e.g.
/// `NullRepository` before login) the observations are empty, finished streams
/// and `fillDocumentQuery` throws.
extension DocumentStore {
  /// The stable key for a list query, computed without touching the network, so
  /// the list can subscribe to whatever is already cached (offline-first) before
  /// — or independently of — the network fill. `nil` without a caching backend.
  public func documentQueryKey(filter: FilterState) -> QueryKey? {
    guard let backend = session?.backend else { return nil }
    return QueryKey(serverID: backend.serverID, filter: filter)
  }

  /// Eager full-fill of a list: await page 1 + count, then background-page the
  /// rest. The returned handle carries the `QueryKey` the list then observes.
  ///
  /// Always `.list` for the meter: this surface exists for the document list UI,
  /// i.e. a user opening, switching or refreshing a view. The proactive sweep
  /// reaches `fillQuery` directly and books itself as `.fill`.
  public func fillDocumentQuery(filter: FilterState) async throws -> QueryFillHandle {
    guard let backend = session?.backend else {
      throw CachingRepositoryError.cacheMiss
    }
    return try await backend.fillQuery(filter: filter, category: .list)
  }

  /// Live growing-prefix of a cached query's ordered answer (the list's data).
  /// Entries are `.loaded` documents or `.skeleton(id:)` placeholders for members
  /// whose object isn't cached yet.
  public func observeDocumentPrefix(
    queryKey: QueryKey, limit: Int
  ) -> AsyncThrowingStream<[DocumentEntry], Error> {
    guard let backend = session?.backend else { return Self.emptyStream() }
    return backend.database.observeDocumentPrefix(
      queryKey: queryKey, serverID: backend.serverID, limit: limit)
  }

  /// Live status of a cached query (server total, order-stale flag).
  public func observeQueryStatus(
    queryKey: QueryKey
  ) -> AsyncThrowingStream<QueryStatus, Error> {
    guard let backend = session?.backend else { return Self.emptyStream() }
    return backend.database.observeQueryStatus(queryKey: queryKey, serverID: backend.serverID)
  }

  /// Throttled remote-delete reconcile on the active server, run by its session:
  /// drop cached documents that no longer exist on the server (so they disappear
  /// from every offline list), fold in the changed-metadata delta, then rebuild
  /// saved-view membership. Soft-fail (background); kicked from `sync()`.
  /// `userInitiated` bypasses the throttle.
  public func reconcileDocuments(userInitiated: Bool = false) async {
    await session?.reconcileDocuments(force: userInitiated)
  }

  /// Run the active server's proactive *Entire library* fill — every query's
  /// pages, then the per-document details — when `phases` calls for it.
  /// Foreground-only; soft-fail (offline-tolerant). `force` ignores the
  /// freshness marker (e.g. the user just enabled the setting).
  ///
  /// Takes the planner's decision rather than an `unmetered` flag. The flag was
  /// the last survivor of the vocabulary ``SyncPhases`` replaced: every caller
  /// held a raw fact about the link, re-derived the fill rule from it, and
  /// passed the answer down — the same shape, one layer lower, that the sweep
  /// stopped doing when `SyncPlan` began emitting phases. Callers now ask
  /// ``SyncPlan/phases(isEntireLibrary:condition:)`` the question the sweep
  /// asks, and a caller that means "everything, the user said so" says `.full`
  /// instead of lying about the network.
  ///
  /// The two fills are one call because they are one decision: `.fill` covers
  /// both, and the details must be walked *after* the pages that put their rows
  /// on disk. Every caller already paired them — except the one that forgot,
  /// leaving notes and file metadata to wait for the next launch.
  public func fillIfEnabled(phases: SyncPhases, force: Bool = false) async {
    guard phases.contains(.fill) else { return }
    // One session for both halves: re-reading it between them would page one
    // server's library and then walk a different server's details.
    guard let session else { return }
    await session.fillLibrary(force: force)
    await session.fillDocumentDetails()
  }

  /// The server's total for the default document list, from the cached query
  /// status — no request. `nil` when there's no caching backend, or when that
  /// list hasn't been fetched yet and so has no recorded total.
  ///
  /// A one-shot read of a live stream: callers want the size to make a decision
  /// (whether to suggest *Entire library*), not to track it.
  public func libraryDocumentCount() async -> UInt? {
    guard let key = documentQueryKey(filter: .default) else { return nil }
    do {
      for try await status in observeQueryStatus(queryKey: key) {
        return status.totalCount
      }
    } catch {
      Logger.shared.info("Library size lookup failed (suppressed): \(error)")
    }
    return nil
  }

  /// Live single document by id, for detail/preview surfaces that must repaint on
  /// mutation/sync.
  public func observeDocument(id: UInt) -> AsyncThrowingStream<Document?, Error> {
    guard let backend = session?.backend else { return Self.emptyStream() }
    return backend.database.observeDocument(serverID: backend.serverID, id: id)
  }

  private static func emptyStream<T: Sendable>() -> AsyncThrowingStream<T, Error> {
    AsyncThrowingStream { $0.finish() }
  }

  /// Debug / maintenance: wipe *all* locally cached data — the GRDB element +
  /// document caches (including the per-server sync cursors: delta watermark and
  /// library-coverage marker, which `clearCache` resets so the reconcile
  /// re-baselines and the fill re-runs over the now-empty cache), the downloaded
  /// PDF/thumbnail blobs, and the in-memory and on-disk image caches — while
  /// keeping the configured server connections. The live observations repaint
  /// empty immediately; the next sync / list open refills from the network.
  ///
  /// `async` because `clearCache` is a cache-table write and no longer offers a
  /// blocking form (see the rule in `Database+Connections`) — a `DELETE` across
  /// every cache table is exactly the kind of transaction that must not sit on
  /// the main thread.
  public func wipeLocalCache() async throws {
    if let backend = session?.backend {
      try await backend.database.clearCache()
    }
    // Downloaded originals/archives/thumbnails (app-group blob store). Rooted at
    // the app group, so a fresh handle addresses the same files the repository
    // wrote — no need to reach into the active repository.
    if let contentStore = try? ContentStore() {
      try? contentStore.purge()
    }
    // Nuke memory + disk image cache.
    imagePipeline.cache.removeAll()
  }
}

//// Permissions checking for resources
extension DocumentStore {
  /// The optimistic ``permissions`` default isn't enough for these three: they
  /// also consult `currentUser`, which is nil until `ui_settings` lands, so
  /// `currentUser?.canView(document) ?? false` would still deny every document
  /// on a cold start. Answer optimistically until we know — the server still
  /// refuses anything the user may not do, and a wrong "you don't have
  /// permission" banner is worse than an edit that fails.
  public func userCanView(document: Document) -> Bool {
    guard permissionsKnown else { return true }
    if !permissions.test(.view, for: .document) {
      return false
    }

    return currentUser?.canView(document) ?? false
  }

  public func userCanChange(document: Document) -> Bool {
    guard permissionsKnown else { return true }
    if !permissions.test(.change, for: .document) {
      return false
    }

    return currentUser?.canChange(document) ?? false
  }

  public func userCanDelete(document: Document) -> Bool {
    guard permissionsKnown else { return true }
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
