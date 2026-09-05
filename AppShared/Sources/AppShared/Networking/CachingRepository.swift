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

/// Freshness policy for the per-server proactive full-library fill.
///
/// The fill is skipped while the last-completed timestamp (in `server_sync_state`)
/// is younger than ``maxAge``, so it runs once and then re-runs only as a periodic
/// backstop — in particular a cold launch after a long quiet period (few/no
/// activation sweeps) finds a stale marker and re-fills. Non-generic so the
/// `static` constant is legal (it wouldn't be on the generic `CachingRepository`).
enum LibraryCoverage {
  /// Re-run the full fill at most this often as a backstop (the cheap activation
  /// sweeps keep things current in between). Daily rather than weekly: the delta
  /// and the membership sweep carry freshness, so a full pass mostly re-confirms
  /// membership — and this interval also bounds how long any gap they miss can
  /// persist.
  static let maxAge: TimeInterval = 24 * 60 * 60

  static func isFresh(_ completedAt: Date?, now: Date = Date()) -> Bool {
    guard let completedAt else { return false }
    return now.timeIntervalSince(completedAt) < maxAge
  }
}

/// The cache control surface the store reaches for, kept off the `Repository`
/// protocol (which stays technology-agnostic). A repository that isn't a
/// `CachingBackend` (preview, Share Extension, tests) makes the store fall back
/// to direct-network behavior.
@MainActor
public protocol CachingBackend: AnyObject, Sendable {
  /// Fetch every element collection from the network and reconcile it into the
  /// local cache. Throws if the sync as a whole fails (e.g. offline); a single
  /// resource the user lacks permission for is skipped, not fatal.
  func syncElements(progress: SyncProgressReporter?) async throws

  /// Eager full-fill of a document list: await page 1 (so the first
  /// window + an exact count land synchronously), write it as the query's order,
  /// then background-page the rest of the query to the cache. The returned
  /// ``QueryFillHandle`` carries the `QueryKey` the list observes and a cancel
  /// handle for the in-flight fill. Throws if page 1 fails (offline → the list
  /// falls back to whatever is already cached).
  ///
  /// **Deliberately not capped by `OfflineBrowsingMode`.** Scrolling only widens
  /// the observed prefix over local rows — it makes no network call — so a size
  /// cap here would become a hard ceiling on what is reachable *even online*.
  /// Removing that ceiling needs a real on-scroll fetch trigger (R3b), not a
  /// cap; until users ask for it, every opened view eager-fills in full.
  func fillQuery(filter: FilterState) async throws -> QueryFillHandle

  /// Proactive one-time coverage fill (*Entire library*): page the
  /// default list and every saved view, stamping rows `.full`, so the whole
  /// active-server library browses offline even if never opened. Sequential
  /// (one query's background paging completes before the next starts). Guarded by
  /// a per-server freshness marker so it runs once and re-runs only as a periodic
  /// backstop; `force` ignores the marker. A failing view doesn't abort the
  /// sweep and still advances the marker — one rejected saved view would
  /// otherwise pin "last full sync" at Never — but a pass in which *every* view
  /// failed advances nothing, so it retries.
  func fillLibrary(force: Bool, progress: SyncProgressReporter?) async throws

  /// Proactive per-document detail fill (*Entire library*): give every
  /// cached document its notes and file-metadata so it's fully renderable
  /// offline even if never opened. Zero-note documents are seeded from the
  /// list payload's notes *count* for free (no request); only documents that
  /// actually have notes, and versions whose `/metadata/` isn't cached, cost a
  /// request. Driven off what's still missing, so it resumes rather than
  /// restarts; uncapped, reporting progress, stopped only by cancellation. Runs
  /// after `fillLibrary`. No-op unless *Entire library* is enabled.
  func fillDocumentDetails(progress: SyncProgressReporter?) async throws

  /// Rebuild the cached membership (`query_order`) of the default list and every
  /// saved view from the cheap Tier-0 id projection, so documents that newly
  /// entered a view appear offline. Only ids with a cached `document` row are
  /// added (their detail arrives via R3δ in the same reconcile). No-op unless
  /// *Entire library* is enabled.
  func reconcileSavedViewMembership() async throws

  /// Remote-delete reconcile (R2): fetch the server's authoritative live id set
  /// and drop every cached document absent from it — `deleteDocuments` explicitly
  /// prunes it from every cached `query_order` too (there is no FK from `document`
  /// to `query_order`, dropped in migration V6 so a row can dangle as a skeleton).
  /// No-op when nothing is cached. Paperless has no deletion feed, so this
  /// periodic sweep is how deletes (and trashings) disappear locally.
  func reconcileDocumentDeletions() async throws

  /// Changed-metadata delta (R3δ): page forward from the per-server watermark
  /// and refresh the cached rows that changed, keeping already-cached documents
  /// fresh without re-opening their list.
  ///
  /// Detection is by `modified`, so it only sees what the server timestamps.
  /// Servers older than paperless-ngx#13170 don't bump `modified` on a version
  /// add/delete/label change; on those the delta stays blind to version-only
  /// edits, and the list fill or detail write-through corrects them instead.
  func reconcileDocumentChanges(progress: SyncProgressReporter?) async throws

  /// The shared database and the active server this repository caches into.
  /// `DocumentStore` reads these to point its `ElementStore` projection at the
  /// same `(database, serverID)` the writes land in, so the live observation
  /// sees them.
  var database: Database { get }
  var serverID: UUID { get }

  /// This server's offline browsing mode (per-server; read live from the
  /// `server` row). The reconcile sweeps and the proactive fill branch on it.
  ///
  /// Stays synchronous: `server` is the one table whose accessors may block
  /// (see the rule in `Database+Connections`), and this is a single-row read of
  /// a handful of rows.
  var offlineBrowsingMode: OfflineBrowsingMode { get }
}

extension CachingBackend {
  /// Progress is optional; the sweeps are just as correct unobserved.
  public func syncElements() async throws {
    try await syncElements(progress: nil)
  }

  public func fillLibrary(force: Bool) async throws {
    try await fillLibrary(force: force, progress: nil)
  }

  public func fillDocumentDetails() async throws {
    try await fillDocumentDetails(progress: nil)
  }

  public func reconcileDocumentChanges() async throws {
    try await reconcileDocumentChanges(progress: nil)
  }
}

enum CachingRepositoryError: Error {
  /// A pure cache read found nothing for a non-optional resource. The store's
  /// hydrate path tolerates this (cold cache); `sync` then fills it.
  case cacheMiss
}

@MainActor
public final class CachingRepository<Wrapped: Repository>: Repository, CachingBackend {
  /// Module-internal rather than `private` only so
  /// ``DocumentStore/previewRepository(as:)`` can recover the underlying
  /// repository for its preview-only helpers. It stays read-only to everyone
  /// (including this module) by being a `let`.
  let wrapped: Wrapped
  public let database: Database
  public let serverID: UUID

  /// The in-flight fill per `QueryKey` — page 1 included, not only the
  /// background continuation. Every writer of a key's `query_order` consults
  /// this: a new fill drains the current owner before touching the key, and the
  /// membership sweep steps over a key that is mid-fill. Main-actor isolated
  /// like the rest of this class, so claiming and clearing never interleave.
  private var activeFills: [QueryKey: Task<Void, any Error>] = [:]

  public init(wrapping: Wrapped, database: Database, serverID: UUID) {
    wrapped = wrapping
    self.database = database
    self.serverID = serverID
  }

  public var offlineBrowsingMode: OfflineBrowsingMode {
    guard let raw = (try? database.connection(id: serverID))?.offlineBrowsingMode,
      let mode = OfflineBrowsingMode(rawValue: raw)
    else { return .recentlyBrowsed }
    return mode
  }

  /// Friendly-name + UUID for sync logs (see ``StoredConnection/logLabel``);
  /// falls back to the bare UUID if the connection row can't be read.
  private var serverLogLabel: String {
    guard let record = try? database.connection(id: serverID) else {
      return "[\(serverID.uuidString)]"
    }
    return StoredConnection(record: record).logLabel
  }

  // MARK: - CachingBackend

  public func syncElements(progress: SyncProgressReporter?) async throws {
    // Sync UI settings *first*: its permission matrix gates the rest, so we
    // don't ask the server for collections the user can't view (doomed 403s).
    // When the matrix is unavailable (uiSettings failed and nothing is cached),
    // `gate` is nil and we fetch everything, relying on the per-resource
    // 403/401-skip in `syncCollection` as a fallback.
    let gate = await syncUISettings()
    func canView(_ resource: UserPermissions.Resource) -> Bool {
      gate?.test(.view, for: resource) ?? true
    }

    // Counted as the group is built, so the total is final before the first
    // completion is awaited. Collections the user can't view are never added,
    // so the bar measures the work actually being done rather than a nominal
    // eight-of-eight that a restricted account can never reach.
    var total = 0
    var completed = 0
    defer { progress?(nil) }
    progress?(SyncActivity(stage: .elementSync))

    try await withThrowingTaskGroup(of: Void.self) { group in
      if canView(.tag) {
        total += 1
        group.addTask { [self] in
          try await syncCollection(TagRecord.self) { try await wrapped.tags() }
        }
      }
      if canView(.correspondent) {
        total += 1
        group.addTask { [self] in
          try await syncCollection(CorrespondentRecord.self) {
            try await wrapped.correspondents()
          }
        }
      }
      if canView(.documentType) {
        total += 1
        group.addTask { [self] in
          try await syncCollection(DocumentTypeRecord.self) {
            try await wrapped.documentTypes()
          }
        }
      }
      if canView(.storagePath) {
        total += 1
        group.addTask { [self] in
          try await syncCollection(StoragePathRecord.self) {
            try await wrapped.storagePaths()
          }
        }
      }
      if canView(.savedView) {
        total += 1
        group.addTask { [self] in
          try await syncCollection(SavedViewRecord.self) { try await wrapped.savedViews() }
        }
      }
      if canView(.user) {
        total += 1
        group.addTask { [self] in
          try await syncCollection(UserRecord.self) { try await wrapped.users() }
        }
      }
      if canView(.group) {
        total += 1
        group.addTask { [self] in
          try await syncCollection(UserGroupRecord.self) { try await wrapped.groups() }
        }
      }
      if canView(.customField) {
        total += 1
        group.addTask { [self] in
          try await syncCollection(CustomFieldRecord.self) {
            try await wrapped.customFields()
          }
        }
      }
      total += 1
      group.addTask { [self] in try await syncServerConfiguration() }

      for try await _ in group {
        completed += 1
        progress?(
          SyncActivity(stage: .elementSync, completed: completed, total: total))
      }
    }
  }

  /// Fill a query's membership + document rows from the list source, which always
  /// carries full object detail (`full_perms`), so every cached row is written at
  /// `.full`. Page 1 is awaited (first window + exact count); the rest pages in
  /// the background. Shared by the interactive on-open path and the proactive
  /// library fill.
  public func fillQuery(filter: FilterState) async throws -> QueryFillHandle {
    let key = QueryKey(serverID: serverID, filter: filter)

    // Two fills on one key used to interleave: the newcomer's page-1
    // `replaceAll: true` deletes every `query_order` row for the key, and the
    // older fill then keeps appending from its own position counter, leaving a
    // hole only a later full fill repairs. Neither write errors — the primary
    // key is ON CONFLICT REPLACE and the unique key ON CONFLICT IGNORE — so
    // nothing notices. Routine rather than hypothetical since the foreground
    // library fill started paging `[(nil, .default)] + savedViews`, the very
    // keys an open list is filling.
    await drainFill(for: key)

    let source = try wrapped.documents(filter: filter)
    let pageSize = Endpoint.defaultDocumentPageSize
    let database = database
    let serverID = serverID

    // Page 1 is still awaited by the caller (first window on screen + the exact
    // total for the count pill) but is written from inside the fill's own task,
    // so the key has a single owner from its very first write. Written from the
    // caller's context it was unclaimed until the background task existed, and
    // the membership sweep's whole-key `replaceQueryOrder` could land in that
    // gap — after which the fill appended page 2 onto a different ordering.
    // Detached tasks inherit no task-local, so re-establish `.fill` here.
    let (firstPage, pageOne) = AsyncThrowingStream<UInt?, any Error>.makeStream()
    let task = Task.detached(priority: .utility) {
      try await NetworkTransfer.$category.withValue(.fill) {
        var position = 0
        do {
          let batch = try await source.fetch(limit: pageSize)
          let total = await source.totalCount
          try await database.writeQueryPage(
            queryKey: key, serverID: serverID, documents: batch,
            startPosition: 0, totalCount: total, replaceAll: true)
          position = batch.count
          pageOne.yield(total)
          pageOne.finish()
        } catch {
          // Page 1 is the caller's problem, not the background's: offline on
          // open means the list falls back to whatever is already cached. The
          // caller sees it through the stream, so this task ends quietly.
          pageOne.finish(throwing: error)
          return
        }

        // Background-page the rest to disk (append). When this completes the
        // whole view is local; scrolling then needs no network (v1).
        while true {
          // Cancellation ends the fill as an error, not as a quiet `break`.
          // The key is truncated either way, and a silent stop is exactly how
          // a caller came to treat a 250-row order as the whole query.
          try Task.checkCancellation()
          if await source.isExhausted { break }
          let batch = try await source.fetch(limit: pageSize)
          if batch.isEmpty { break }
          // Re-check between the fetch returning and the write. Cancellation is
          // how a newer fill takes the key over, and by now its page-1 replace
          // may already have landed — writing here would graft our stale
          // positions onto its rows.
          try Task.checkCancellation()
          try await database.writeQueryPage(
            queryKey: key, serverID: serverID, documents: batch,
            startPosition: position, totalCount: await source.totalCount,
            replaceAll: false)
          position += batch.count
        }

        // Reached the end of the query: the cached order is now its complete
        // membership, and only here is that recorded. Page 1's `replaceAll`
        // cleared the stamp, so anything that stopped us short leaves the key
        // marked incomplete for the next pass to redo.
        try await database.markQueryFillComplete(queryKey: key, serverID: serverID)
      }
    }

    activeFills[key] = task
    Task { [weak self] in
      do {
        try await task.value
      } catch is CancellationError {
        // A newer fill drained us, or the view went away. Expected.
      } catch {
        // `fillLibrary` awaits the fill and reports its failure where the user
        // can see it. The interactive path doesn't await the background paging
        // at all, so without this its failures would be entirely silent.
        Logger.sync.error("Background query fill failed: \(error)")
      }
      // Retract only our own registration: a newer fill may have drained and
      // replaced us while this was waiting.
      guard let self, activeFills[key] == task else { return }
      activeFills[key] = nil
    }

    // A cancelled caller takes the whole fill with it — the task is detached,
    // so nothing else would — and still reports the cancellation, as it did
    // when page 1 ran in the caller's own context.
    let total = try await withTaskCancellationHandler {
      var total: UInt?
      for try await value in firstPage { total = value }
      return total
    } onCancel: {
      task.cancel()
    }
    try Task.checkCancellation()
    return QueryFillHandle(queryKey: key, totalCount: total, fillTask: task)
  }

  /// Stop the fill that currently owns `key` and wait for it to actually stop.
  /// Cancellation is cooperative — the loop only checks between pages — so
  /// returning without the await would leave a writer alive across the caller's
  /// own write, which is the whole problem being fixed.
  private func drainFill(for key: QueryKey) async {
    guard let owner = activeFills[key] else { return }
    owner.cancel()
    // Its outcome is the departing fill's own business (its registration task
    // logs it) — all this needs is for it to have stopped writing.
    _ = try? await owner.value
    if activeFills[key] == owner { activeFills[key] = nil }
  }

  /// Whether a fill currently owns this key's `query_order`.
  private func isFilling(_ key: QueryKey) -> Bool { activeFills[key] != nil }

  public func fillLibrary(force: Bool, progress: SyncProgressReporter?) async throws {
    // Read the marker before the guard rather than inside it: `||`'s right-hand
    // side is an `@autoclosure`, which cannot be `async`.
    let coverage = try? await database.libraryCoverageAt(serverID: serverID)
    guard force || !LibraryCoverage.isFresh(coverage) else { return }

    // Claim the stage before the saved-view read, so the setup isn't a gap the
    // screen renders as "Idle".
    defer { progress?(nil) }
    progress?(SyncActivity(stage: .libraryFill))

    // Default list first, then every cached saved view (synced by `syncElements`
    // just before this in the foreground trigger). Build the *same* FilterState
    // the UI observes so the filled QueryKeys match its subscriptions. A `nil`
    // name denotes the default list (used to label a failure for the UI).
    let savedViews = try await database.elements(SavedViewRecord.self, serverID: serverID)
    let views: [(name: String?, filter: FilterState)] =
      [(nil, .default)] + savedViews.map { ($0.name, FilterState(savedView: $0)) }

    var succeeded = 0
    Logger.sync.info(
      "Library fill: \(views.count, privacy: .public) view(s) for server \(self.serverLogLabel, privacy: .public)"
    )
    for (index, (name, filter)) in views.enumerated() {
      try Task.checkCancellation()
      // A downgrade mid-fill means the rest of these views are no longer wanted,
      // and `reclaimAfterDowngrade` runs right behind us — continuing would
      // write back rows it has just reclaimed. One connection-row read per view,
      // and there are few views.
      guard offlineBrowsingMode == .entireLibrary else {
        Logger.sync.info("Library fill: mode left Entire library mid-pass; stopping")
        return
      }
      progress?(
        SyncActivity(
          stage: .libraryFill, detail: name, completed: index, total: views.count))
      let key = QueryKey(serverID: serverID, filter: filter)
      do {
        // Sequential: let each query's background paging finish before the next,
        // so we never run N concurrent paging chains against the server.
        let handle = try await fillQuery(filter: filter)
        // `fillQuery` pages the rest of the view on a *detached* task, which
        // inherits no cancellation, and awaiting a `Task<Void, Never>` neither
        // throws nor propagates one. Without this bridge the only cancellation
        // this loop can honour is between views — so cancelling mid-view still
        // paged the whole thing, which is exactly what a background time budget
        // or a server switch cannot afford.
        try await withTaskCancellationHandler {
          try await handle.awaitCompletion()
        } onCancel: {
          handle.cancel()
        }
        try Task.checkCancellation()
        // Not just "nothing threw": the stamp is the fill's own word that it
        // paged the query to the end. A truncated order counted as covered
        // would stamp the coverage marker and suppress the retry for a day,
        // leaving the list hard-stopped at whatever page it reached — with the
        // count pill still claiming the server's full total.
        guard
          (try? await database.queryFillCompletedAt(queryKey: key, serverID: serverID))
            ?? nil != nil
        else {
          // A backstop, not the main path: the fill throws on every way of
          // stopping short, so reaching here means the stamp and the outcome
          // disagree. Left as a log rather than a user-facing message — there
          // is nothing to tell the user beyond "it will run again".
          Logger.sync.warning(
            "Library fill: '\(name ?? "default", privacy: .public)' ended incomplete; not counting it as covered"
          )
          continue
        }
        try? await database.clearQuerySyncError(serverID: serverID, queryKey: key.rawValue)
        succeeded += 1
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        // A rejected view (e.g. an advanced full-text query the server won't run)
        // must not block the *whole* library's coverage. Record it so the
        // Offline & Sync screen can warn, and carry on.
        Logger.sync.warning(
          "Library fill: '\(name ?? "default", privacy: .public)' failed (\(error)); skipping")
        try? await database.recordQuerySyncError(
          serverID: serverID, queryKey: key.rawValue, savedViewName: name,
          message: Self.syncFailureMessage(error))
      }
    }

    // A completed pass, not a flawless one: one permanently failing view would
    // otherwise pin "last full sync" at Never. But a pass where *nothing*
    // succeeded cached nothing, and stamping it would suppress retries for
    // `LibraryCoverage.maxAge` while the screen claims a fresh sync over an
    // empty cache — the ordinary shape of Wi-Fi with the server unreachable,
    // since neither `isExpensive` nor `isConstrained` means reachable.
    guard succeeded > 0 else {
      Logger.sync.warning(
        "Library fill: all \(views.count, privacy: .public) views failed; leaving coverage unset")
      return
    }
    try? await database.setLibraryCoverageAt(Date(), serverID: serverID)
  }

  // Documents whose detail fetch failed this session. Without this, a document
  // the server will never serve — a `/notes/` the user has no permission for, a
  // `/metadata/` that 500s on one bad file — is retried on every foreground for
  // as long as the app runs. Per-session (not persisted) so a transient failure
  // clears on the next launch rather than sticking forever.
  private var detailFillFailures: Set<UInt> = []

  public func fillDocumentDetails(progress: SyncProgressReporter?) async throws {
    guard offlineBrowsingMode == .entireLibrary else { return }
    // Before the seed and the two "what's missing" reads: they're quick, but a
    // gap here shows up as the activity flicking back to "Idle".
    progress?(SyncActivity(stage: .detailFill))

    // Free step: every zero-note document gets an empty notes row from the list
    // payload's count — no request — so it renders "no notes" offline and drops
    // out of the fetch set below.
    let seeded = (try? await database.seedEmptyNotesForZeroCountDocuments(serverID: serverID)) ?? 0

    // Then fetch only what's genuinely missing, capped per pass. `try?` per doc
    // so one failure (or going offline mid-pass) doesn't abort the rest; the
    // still-missing set simply shrinks and the next pass resumes.
    var fetchedMetadata = 0
    var fetchedNotes = 0
    defer { progress?(nil) }

    // Notes are a separate resource with their own permission. Without this the
    // fill asks for every noted document's `/notes/` and takes a 403 each time —
    // one doomed request per document, on every foreground, forever. `nil` (no
    // cached matrix yet) stays optimistic, matching `syncElements`.
    let permissions = try? await database.uiSettings(serverID: serverID)?.permissions
    let canViewNotes = permissions?.test(.view, for: .note) ?? true

    try await NetworkTransfer.$category.withValue(.fill) {
      let missingMetadata =
        (try? await database.documentIDsMissingFileMetadata(
          serverID: serverID, excluding: detailFillFailures)) ?? []
      let needsNotes: [UInt] =
        canViewNotes
        ? (try? await database.documentIDsNeedingNotesFetch(
          serverID: serverID, excluding: detailFillFailures)) ?? []
        : []

      // The pass is uncapped: a first cold fill of a large library is meant to
      // run to completion, and the Offline & Sync screen reports it rather than
      // a per-pass budget hiding how much is left. Cancellation (backgrounding,
      // a server switch) is what stops it early, and the work is driven off
      // what's still missing, so the next pass resumes.
      let total = missingMetadata.count + needsNotes.count
      var done = 0
      progress?(SyncActivity(stage: .detailFill, completed: 0, total: total))

      // A per-document report is a main-actor `@Observable` write that
      // repaints the whole Offline & Sync screen; on a fast link that's
      // dozens a second for as long as the pass runs. Coalesce to a cadence
      // no one can perceive as choppy, but always report the final count so
      // the screen doesn't sit one document short of "done".
      var lastReportedAt = Date.distantPast
      @MainActor func reportThrottled() {
        let now = Date()
        guard done == total || now.timeIntervalSince(lastReportedAt) >= 0.1 else { return }
        lastReportedAt = now
        progress?(SyncActivity(stage: .detailFill, completed: done, total: total))
      }

      for id in missingMetadata {
        try Task.checkCancellation()
        if (try? await metadata(documentId: id)) != nil {
          fetchedMetadata += 1
        } else {
          detailFillFailures.insert(id)
        }
        done += 1
        reportThrottled()
      }

      for id in needsNotes {
        try Task.checkCancellation()
        if (try? await notes(documentId: id)) != nil {
          fetchedNotes += 1
        } else {
          detailFillFailures.insert(id)
        }
        done += 1
        reportThrottled()
      }
    }

    Logger.sync.info(
      "Detail fill: seeded \(seeded, privacy: .public) empty-notes rows, fetched \(fetchedNotes, privacy: .public) notes, \(fetchedMetadata, privacy: .public) metadata"
    )
  }

  /// A short, user-facing reason for a failed view sync — prefers the server's
  /// own message (carried in `RequestError`) over a generic description.
  private static func syncFailureMessage(_ error: Error) -> String {
    (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
  }

  private func syncCollection<R: ElementRecord>(
    _ type: R.Type, _ fetch: () async throws -> [R.Domain]
  ) async throws {
    do {
      let domains = try await fetch()
      try await database.replaceElements(domains, of: type, serverID: serverID)
    } catch let error where Self.isSkippable(error) {
      Logger.sync.info(
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
      try await database.setUISettings(settings, serverID: serverID)
      return settings.permissions
    } catch {
      Logger.sync.info(
        "uiSettings sync failed (\(error)); gating sync on cached permissions")
      return try? await database.uiSettings(serverID: serverID)?.permissions
    }
  }

  private func syncServerConfiguration() async throws {
    do {
      let config = try await wrapped.serverConfiguration()
      try await database.setServerConfiguration(config, serverID: serverID)
    } catch let error where Self.isSkippable(error) {
      Logger.sync.info("Skipping serverConfiguration sync: \(error)")
    }
  }

  /// 401 already flips needs-auth via the wrapped decorator; 403 means the user
  /// lacks permission for that one resource. Neither should fail the whole sync.
  ///
  /// Takes `any Error` because a 403 arrives as one of two unrelated types: the
  /// singleton fetches surface `RequestError.forbidden`, while every paginated
  /// collection goes through `PageCursor`, which reports it as
  /// `ResourceForbidden<Element>`. Both must be skippable, or one forbidden
  /// collection takes the whole sync task group down with it.
  private static func isSkippable(_ error: any Error) -> Bool {
    if error is any ResourceForbiddenError { return true }
    return switch error as? RequestError {
    case .forbidden, .unauthorized: true
    default: false
    }
  }

  /// Whether a failed detail fetch may fall back to the offline cache.
  ///
  /// A transport failure means we never got an answer, so the last-known row is
  /// the best one available. A 403/401 *is* the answer: the user may no longer
  /// see this document, and serving the cached title, notes and PDF would hide a
  /// revoked permission behind what looks like an outage. Same predicate as the
  /// sync skip — there a permission failure is tolerated because the rest of the
  /// sync stays valid, here it must propagate because it answers the only
  /// question asked. (404 never reaches this: `ApiRepository.get` maps it to
  /// `nil`, handled on the success path.)
  private static func mayServeCache(after error: any Error) -> Bool {
    !isSkippable(error)
  }

  // MARK: - Element reads (cache)

  public func tags() async throws -> [Tag] {
    try await database.elements(TagRecord.self, serverID: serverID)
  }

  public func correspondents() async throws -> [Correspondent] {
    try await database.elements(CorrespondentRecord.self, serverID: serverID)
  }

  public func documentTypes() async throws -> [DocumentType] {
    try await database.elements(DocumentTypeRecord.self, serverID: serverID)
  }

  public func storagePaths() async throws -> [StoragePath] {
    try await database.elements(StoragePathRecord.self, serverID: serverID)
  }

  public func savedViews() async throws -> [SavedView] {
    try await database.elements(SavedViewRecord.self, serverID: serverID)
  }

  public func users() async throws -> [User] {
    try await database.elements(UserRecord.self, serverID: serverID)
  }

  public func groups() async throws -> [UserGroup] {
    try await database.elements(UserGroupRecord.self, serverID: serverID)
  }

  public func customFields() async throws -> [CustomField] {
    try await database.elements(CustomFieldRecord.self, serverID: serverID)
  }

  public func currentUser() async throws -> User {
    guard let user = try await database.uiSettings(serverID: serverID)?.user else {
      throw CachingRepositoryError.cacheMiss
    }
    return user
  }

  public func uiSettings() async throws -> UISettings {
    guard let settings = try await database.uiSettings(serverID: serverID) else {
      throw CachingRepositoryError.cacheMiss
    }
    return settings
  }

  public func serverConfiguration() async throws -> ServerConfiguration {
    guard let config = try await database.serverConfiguration(serverID: serverID) else {
      throw CachingRepositoryError.cacheMiss
    }
    return config
  }

  // MARK: - Single-element getters (cache-first + network fallback + write-through)

  public func tag(id: UInt) async throws -> Tag? {
    if let cached = try await database.element(TagRecord.self, serverID: serverID, id: id) {
      return cached
    }
    guard let fetched = try await wrapped.tag(id: id) else { return nil }
    try await database.upsertElement(fetched, of: TagRecord.self, serverID: serverID)
    return fetched
  }

  public func correspondent(id: UInt) async throws -> Correspondent? {
    if let cached = try await database.element(CorrespondentRecord.self, serverID: serverID, id: id)
    {
      return cached
    }
    guard let fetched = try await wrapped.correspondent(id: id) else { return nil }
    try await database.upsertElement(fetched, of: CorrespondentRecord.self, serverID: serverID)
    return fetched
  }

  public func documentType(id: UInt) async throws -> DocumentType? {
    if let cached = try await database.element(DocumentTypeRecord.self, serverID: serverID, id: id)
    {
      return cached
    }
    guard let fetched = try await wrapped.documentType(id: id) else { return nil }
    try await database.upsertElement(fetched, of: DocumentTypeRecord.self, serverID: serverID)
    return fetched
  }

  // MARK: - Element mutations (pessimistic: forward + write-through)

  public func create(tag: ProtoTag) async throws -> Tag {
    let created = try await wrapped.create(tag: tag)
    try await database.upsertElement(created, of: TagRecord.self, serverID: serverID)
    return created
  }

  public func update(tag: Tag) async throws -> Tag {
    let updated = try await wrapped.update(tag: tag)
    try await database.upsertElement(updated, of: TagRecord.self, serverID: serverID)
    return updated
  }

  public func delete(tag: Tag) async throws {
    try await wrapped.delete(tag: tag)
    try await database.deleteElement(TagRecord.self, serverID: serverID, id: tag.id)
  }

  public func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
    let created = try await wrapped.create(correspondent: correspondent)
    try await database.upsertElement(created, of: CorrespondentRecord.self, serverID: serverID)
    return created
  }

  public func update(correspondent: Correspondent) async throws -> Correspondent {
    let updated = try await wrapped.update(correspondent: correspondent)
    try await database.upsertElement(updated, of: CorrespondentRecord.self, serverID: serverID)
    return updated
  }

  public func delete(correspondent: Correspondent) async throws {
    try await wrapped.delete(correspondent: correspondent)
    try await database.deleteElement(
      CorrespondentRecord.self, serverID: serverID, id: correspondent.id)
  }

  public func create(documentType: ProtoDocumentType) async throws -> DocumentType {
    let created = try await wrapped.create(documentType: documentType)
    try await database.upsertElement(created, of: DocumentTypeRecord.self, serverID: serverID)
    return created
  }

  public func update(documentType: DocumentType) async throws -> DocumentType {
    let updated = try await wrapped.update(documentType: documentType)
    try await database.upsertElement(updated, of: DocumentTypeRecord.self, serverID: serverID)
    return updated
  }

  public func delete(documentType: DocumentType) async throws {
    try await wrapped.delete(documentType: documentType)
    try await database.deleteElement(
      DocumentTypeRecord.self, serverID: serverID, id: documentType.id)
  }

  public func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
    let created = try await wrapped.create(storagePath: storagePath)
    try await database.upsertElement(created, of: StoragePathRecord.self, serverID: serverID)
    return created
  }

  public func update(storagePath: StoragePath) async throws -> StoragePath {
    let updated = try await wrapped.update(storagePath: storagePath)
    try await database.upsertElement(updated, of: StoragePathRecord.self, serverID: serverID)
    return updated
  }

  public func delete(storagePath: StoragePath) async throws {
    try await wrapped.delete(storagePath: storagePath)
    try await database.deleteElement(StoragePathRecord.self, serverID: serverID, id: storagePath.id)
  }

  public func create(savedView: ProtoSavedView) async throws -> SavedView {
    let created = try await wrapped.create(savedView: savedView)
    try await database.upsertElement(created, of: SavedViewRecord.self, serverID: serverID)
    return created
  }

  public func update(savedView: SavedView) async throws -> SavedView {
    let updated = try await wrapped.update(savedView: savedView)
    try await database.upsertElement(updated, of: SavedViewRecord.self, serverID: serverID)
    return updated
  }

  public func delete(savedView: SavedView) async throws {
    try await wrapped.delete(savedView: savedView)
    try await database.deleteElement(SavedViewRecord.self, serverID: serverID, id: savedView.id)
  }

  // MARK: - Documents (pessimistic write-through + cache fallback)

  public func update(document: Document) async throws -> Document {
    let updated = try await wrapped.update(document: document)
    // Write the confirmed object through; the join observation repaints the row
    // in place. `update` is fetched with `full_perms` (see ApiRepository) so the
    // response carries permissions/custom fields — a `.full` write replaces the
    // row completely without dropping them. Ordering under the active sort isn't
    // recomputed offline — mark affected queries stale.
    try await database.upsertDocument(updated, serverID: serverID)
    try await database.markQueriesOrderStale(containing: updated.id, serverID: serverID)
    return updated
  }

  public func delete(document: Document) async throws {
    try await wrapped.delete(document: document)
    // Explicitly prunes every cached query_order referencing it too — no FK
    // cascade does this (dropped in migration V6).
    try await database.deleteDocuments(serverID: serverID, removedIDs: [document.id])
  }

  public func create(document: ProtoDocument, file: URL, filename: String) async throws {
    try await wrapped.create(document: document, file: file, filename: filename)
  }

  public func document(id: UInt) async throws -> Document? {
    do {
      guard let fetched = try await wrapped.document(id: id) else {
        // A 404 on a single document is not proof it was deleted: an unhealthy
        // or misrouted backend 404s documents that still exist, and evicting the
        // row would take its list membership with it, making an opened document
        // vanish. `reconcileDocumentDeletions` decides deletions against the
        // server's authoritative id set; here we serve the cached row.
        if let cached = try await database.document(serverID: serverID, id: id) {
          Logger.shared.info(
            "document(id:) fetch returned nil (404?); serving cached instead of deleting")
          return cached
        }
        return nil
      }
      // A full-detail fetch — upgrade the row to Tier-2.
      try await database.upsertDocument(fetched, serverID: serverID)
      return fetched
    } catch let error where Self.mayServeCache(after: error) {
      // Offline/transient: serve the last-known cached row (Tier-1 or Tier-2)
      // rather than failing the open. Mirrors the element offline-first policy.
      // A permission failure isn't caught here at all, so it propagates.
      if let cached = try await database.document(serverID: serverID, id: id) {
        Logger.shared.info("document(id:) network failed (\(error)); serving cached")
        return cached
      }
      throw error
    }
  }

  public func document(asn: UInt) async throws -> Document? {
    do {
      guard let fetched = try await wrapped.document(asn: asn) else { return nil }
      try await database.upsertDocument(fetched, serverID: serverID)
      return fetched
    } catch let error where Self.mayServeCache(after: error) {
      if let cached = try await database.document(serverID: serverID, asn: asn) {
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

  public func orderedDocumentIDs(filter: FilterState) async throws -> [UInt] {
    try await wrapped.orderedDocumentIDs(filter: filter)
  }

  public func reconcileDocumentDeletions() async throws {
    let localIDs = try await database.allDocumentIDs(serverID: serverID)
    // Nothing cached yet → nothing to reconcile (skip the id fetch entirely).
    guard !localIDs.isEmpty else { return }

    // The unfiltered list is the complete live id set for the server.
    let serverIDs = Set(try await wrapped.documentIDs(filter: .empty))
    let removed = localIDs.subtracting(serverIDs)
    guard !removed.isEmpty else { return }

    Logger.sync.info(
      "Reconcile: dropping \(removed.count, privacy: .public) remotely-deleted documents")
    try await database.deleteDocuments(serverID: serverID, removedIDs: Array(removed))
  }

  public func reconcileDocumentChanges(progress: SyncProgressReporter?) async throws {
    let entireLibrary = offlineBrowsingMode == .entireLibrary

    // Delta refreshes changed rows. Under *Recently browsed* it only touches
    // already-cached rows (new docs surface via on-open list fills); under
    // *Entire library* it also keeps brand-new docs, so the whole library stays
    // current between full fills. The list payload always carries full object
    // detail; the setting only governs which docs are kept (every row is written
    // at `.full`). Nothing cached ⇒ the proactive fill (or a list open) seeds
    // first.
    let localIDs = try await database.allDocumentIDs(serverID: serverID)
    guard !localIDs.isEmpty else { return }

    guard let watermark = await deltaWatermark() else {
      // First run: establish the baseline from the newest doc; subsequent passes
      // delta against it. (Avoids re-paging the whole library on cold start.)
      var newestFirst = FilterState.empty
      newestFirst.sortField = .modified
      newestFirst.sortOrder = .descending
      let baseline = try wrapped.documents(filter: newestFirst)
      if let newest = try await baseline.fetch(limit: 1).first?.modified {
        await setDeltaWatermark(newest)
      }
      return
    }

    // Oldest-first from the watermark, committing the cursor per page, so an
    // interrupted pass resumes. A newest-first walk can't: a high-water mark
    // only moves up, so once it passes an unapplied change that change is
    // unreachable forever.
    //
    // Uncapped, because a per-pass budget counted *applied* documents — which
    // barely bounds anything under `.recentlyBrowsed`, and under
    // `.entireLibrary` a run of documents sharing one `modified` (one bulk
    // server-side UPDATE) could exhaust it without moving the cursor at all.
    //
    // The server bound is date-granular and exclusive, and `FilterState` widens
    // an inclusive start by a day, so a pass re-fetches from the watermark's day.
    var filter = FilterState.empty
    filter.sortField = .modified
    filter.sortOrder = .ascending
    filter.date.modified = .between(start: watermark, end: nil)
    let source = try wrapped.documents(filter: filter)

    var cursor = watermark
    var applied = 0
    var seen = 0
    defer { progress?(nil) }
    while true {
      // Per page, so a pass that is cancelled — or killed on a background time
      // budget — stops here with the cursor committed rather than mid-write.
      try Task.checkCancellation()
      let batch = try await source.fetch(limit: Endpoint.defaultDocumentPageSize)
      if batch.isEmpty { break }
      seen += batch.count
      let total = await source.totalCount
      progress?(
        SyncActivity(
          stage: .reconcile, completed: seen, total: total.map { Int($0) }))

      var changed: [Document] = []
      for document in batch {
        guard let modified = document.modified else { continue }
        // Strict `<` so documents sharing the cursor's exact timestamp are
        // re-applied rather than dropped; the upsert is a straight replace, so
        // repeating one costs nothing.
        if modified < cursor { continue }
        changed.append(document)
        if modified > cursor { cursor = modified }
      }

      // *Entire library*: keep every changed/new doc. *Recently browsed*: only
      // refresh rows already cached. Either way the row is written at `.full`.
      let toUpsert = entireLibrary ? changed : changed.filter { localIDs.contains($0.id) }
      if !toUpsert.isEmpty {
        Logger.sync.info(
          "Reconcile: refreshing \(toUpsert.count, privacy: .public) changed documents")
        try await database.upsertDocuments(toUpsert, serverID: serverID)
        // Note edits bump `modified`, so a changed doc's cached notes may be
        // stale. Drop them (cheap, local) — the upsert above just refreshed each
        // doc's `notesCount`, so the next `fillDocumentDetails` re-seeds an empty
        // row for free when the count is 0, or re-fetches when it's > 0. We can't
        // tell a note change from any other field change, so this may re-fetch a
        // few docs whose notes didn't actually change.
        try? await database.invalidateNotes(serverID: serverID, documentIDs: toUpsert.map(\.id))
        applied += toUpsert.count
      }
      // Commit the cursor per page rather than once at the end — this is what
      // makes an interrupted pass resume instead of restart.
      if cursor > watermark {
        await setDeltaWatermark(cursor)
      }
      if await source.isExhausted { break }
    }
  }

  public func reconcileSavedViewMembership() async throws {
    guard offlineBrowsingMode == .entireLibrary else { return }
    // Nothing cached ⇒ the proactive fill seeds membership first.
    guard try await !database.allDocumentIDs(serverID: serverID).isEmpty else { return }

    // Rebuild the default list + each saved view's order from the cheap Tier-0 id
    // projection. Runs *after* the R3δ pass (which lands new docs at detail), so
    // newly-matched ids already have a `document` row for the FK.
    let savedViews = try await database.elements(SavedViewRecord.self, serverID: serverID)
    let views: [(name: String?, filter: FilterState)] =
      [(nil, .default)] + savedViews.map { ($0.name, FilterState(savedView: $0)) }
    for (name, filter) in views {
      try Task.checkCancellation()
      let key = QueryKey(serverID: serverID, filter: filter)
      // A fill owning this key is writing the same `query_order` rows page by
      // page, and it writes a strictly better ordering than this Tier-0
      // projection — it carries full document detail, and its page-1 replace has
      // already re-baselined the key. Interleaving `replaceQueryOrder`'s
      // delete-all-and-reinsert with the fill's appends silently merges two
      // orderings into a garbled one, so leave the key to the fill; the next
      // sweep picks it up.
      guard !isFilling(key) else {
        Logger.sync.info(
          "Membership sweep: '\(name ?? "default", privacy: .public)' is mid-fill; skipping")
        continue
      }
      do {
        // Ordered, not the id-set projection: these ids become `query_order`
        // positions verbatim, so the query's own sort has to survive the round
        // trip or the sweep rewrites every cached list to id order.
        let ids = try await wrapped.orderedDocumentIDs(filter: filter)
        // Re-check after the fetch: that suspension is exactly the window a
        // fill can start in, and the guard above would then be stale.
        guard !isFilling(key) else {
          Logger.sync.info(
            "Membership sweep: '\(name ?? "default", privacy: .public)' began filling; skipping")
          continue
        }
        try await database.replaceQueryOrder(
          queryKey: key, serverID: serverID, orderedIDs: ids)
        try? await database.clearQuerySyncError(serverID: serverID, queryKey: key.rawValue)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        Logger.sync.info(
          "Membership sweep: '\(name ?? "default", privacy: .public)' failed (\(error)); continuing"
        )
        try? await database.recordQuerySyncError(
          serverID: serverID, queryKey: key.rawValue, savedViewName: name,
          message: Self.syncFailureMessage(error))
      }
    }
  }

  // Per-server delta watermark (newest `modified` applied), in `server_sync_state`
  // keyed by serverID. Regenerable sync state — `clearCache` resets it, and
  // losing it just re-baselines on the next pass.
  private func deltaWatermark() async -> Date? {
    try? await database.deltaWatermark(serverID: serverID)
  }

  private func setDeltaWatermark(_ date: Date) async {
    do {
      try await database.setDeltaWatermark(date, serverID: serverID)
    } catch {
      Logger.sync.error("setDeltaWatermark failed: \(error)")
    }
  }

  public func nextAsn() async throws -> UInt {
    try await wrapped.nextAsn()
  }

  /// The version id a document's file-metadata caches under. Both fallbacks
  /// land on the document id, which equals the root version id server-side: the
  /// cached row may be absent (nothing fetched it yet) and the read itself may
  /// fail. In practice the detail view fetches the document first, so the
  /// versions are usually known by the time this is called.
  private func fileMetadataVersionID(documentId: UInt) async -> UInt {
    (try? await database.document(serverID: serverID, id: documentId))?.currentVersionID
      ?? documentId
  }

  public func metadata(documentId: UInt) async throws -> Metadata {
    // File-metadata is immutable per file version, so it caches under the
    // document's current version id.
    let versionID = await fileMetadataVersionID(documentId: documentId)
    do {
      let fetched = try await wrapped.metadata(documentId: documentId)
      try await database.setFileMetadata(fetched, serverID: serverID, versionID: versionID)
      return fetched
    } catch let error where Self.mayServeCache(after: error) {
      if let cached = try await database.fileMetadata(serverID: serverID, versionID: versionID) {
        Logger.shared.info("metadata(documentId:) network failed (\(error)); serving cached")
        return cached
      }
      throw error
    }
  }

  public func notes(documentId: UInt) async throws -> [Document.Note] {
    do {
      let fetched = try await wrapped.notes(documentId: documentId)
      try await database.setNotes(fetched, serverID: serverID, documentID: documentId)
      return fetched
    } catch let error where Self.mayServeCache(after: error) {
      // `nil` (never cached) is distinct from `[]` (cached, no notes): only the
      // former propagates the network error.
      if let cached = try await database.notes(serverID: serverID, documentID: documentId) {
        Logger.shared.info("notes(documentId:) network failed (\(error)); serving cached")
        return cached
      }
      throw error
    }
  }

  public func createNote(documentId: UInt, note: ProtoDocument.Note) async throws
    -> [Document.Note]
  {
    // Pessimistic: the server returns the updated full list, which we write
    // through so the cached notes stay consistent without a re-fetch.
    let updated = try await wrapped.createNote(documentId: documentId, note: note)
    try await database.setNotes(updated, serverID: serverID, documentID: documentId)
    return updated
  }

  public func deleteNote(id: UInt, documentId: UInt) async throws -> [Document.Note] {
    let updated = try await wrapped.deleteNote(id: id, documentId: documentId)
    try await database.setNotes(updated, serverID: serverID, documentID: documentId)
    return updated
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
    if let current = try await database.uiSettings(serverID: serverID) {
      let merged = UISettings(
        user: current.user, settings: settings, permissions: current.permissions)
      try await database.setUISettings(merged, serverID: serverID)
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
