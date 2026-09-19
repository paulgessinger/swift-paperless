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

/// Policy for the proactive per-document detail fill. Non-generic for the same
/// reason as ``LibraryCoverage``.
enum DetailFillPolicy {
  /// How many documents the detail fill gets through between re-reads of the
  /// server's offline browsing mode, to notice a downgrade mid-pass. Not per
  /// document: the `server` row's accessors block, and this loop runs over the
  /// whole library.
  static let downgradeCheckStride = 32
}

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

/// Retention policy for the per-server reachability GC of cached query keys.
/// Non-generic so the `static` constant is legal (it wouldn't be on the generic
/// `CachingRepository`), same as ``LibraryCoverage`` above.
enum QueryRetentionPolicy {
  /// How many *ad-hoc* query keys — a filter/sort combination that is neither
  /// the default list nor a saved view — survive the sweep, most recently filled
  /// first.
  ///
  /// Twenty rather than a handful or a hundred: what the retention buys is "go
  /// back to what I was just looking at and it's still there offline", which is
  /// a session's worth of browsing, not a history. Each retained key costs one
  /// `query_order` row per member document *and* — through the anti-join in
  /// `pruneUnreferencedDocuments` — pins every document it lists, so this is
  /// really a cap on how much of the library an abandoned filter can keep alive.
  static let recentAdHocCap = 20

  /// How long a viewed list stays exempt from the *Recently browsed* cap
  /// (`OfflineLibrarySize.recentlyBrowsedDefaultListCap` rows per list).
  ///
  /// Recency rather than position decides *which* lists get cut back: a list the
  /// user just browsed stays whole, so the older documents they scrolled down to
  /// are still there offline, and storage settles back to the cap once they've
  /// moved on. A day rather than a session: "browsed this morning, offline on the
  /// train tonight" is the case the mode is named for, and it matches the *Entire
  /// library* coverage backstop (``LibraryCoverage/maxAge``).
  static let recentlyBrowsedGrace: TimeInterval = 24 * 60 * 60
}

/// How a detail-fill pass that ran to the end left things.
public struct DetailFillOutcome: Sendable {
  /// The first failure this pass hit that is worth surfacing (see
  /// `SyncFailureClass.firstSurfaced`); `nil` if nothing failed, or only for
  /// reasons that aren't shown (offline, 401/403).
  public var failure: (any Error)?

  /// How many fetches failed in this pass, whatever the reason. Those
  /// documents are still missing, and the next pass tries them again.
  public var failed: Int

  public static let complete = DetailFillOutcome(failure: nil, failed: 0)
}

/// The cache control surface the store reaches for, kept off the `Repository`
/// protocol (which stays technology-agnostic). A repository that isn't a
/// `CachingBackend` (preview, Share Extension, tests) makes the store fall back
/// to direct-network behavior.
@MainActor
public protocol CachingBackend: AnyObject, Sendable {
  /// Fetch the permissions / UI-settings singleton and write it to the cache.
  ///
  /// Called immediately before ``syncElements(progress:)``, as its own step so
  /// the caller can record its outcome independently of the element phase.
  func syncUISettings() async throws

  /// Fetch every element collection from the network and reconcile it into the
  /// local cache. Throws if the sync as a whole fails (e.g. offline); a single
  /// resource the user lacks permission for is skipped, not fatal.
  ///
  /// Gated on the *cached* permission matrix, which ``syncUISettings()`` has
  /// just refreshed — or failed to, leaving the last known one, or none at all.
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
  ///
  /// `category` says who asked: the same code serves an interactive list open
  /// and the proactive library sweep, and the transfer meter has to tell those
  /// apart. It is a parameter rather than the ambient task-local because the
  /// paging runs on a detached task, which inherits no task-local.
  func fillQuery(filter: FilterState, category: TransferCategory) async throws -> QueryFillHandle

  /// Suspend until nothing is writing `key`'s cached order: no fill, and no
  /// membership or reachability sweep holding the key.
  ///
  /// How a list follows a fill that took its query over. The newer fill cancels
  /// the list's and the list never sees its handle, so it waits here for the
  /// key to settle and then reads the cache's completeness. Follows successive
  /// owners (a fill drained by yet another one), and returns early if the
  /// calling task is cancelled.
  func waitForQueryWriters(_ key: QueryKey) async

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
  ///
  /// A document whose `/notes/` or `/metadata/` fails doesn't abort the pass,
  /// and is tried again on the next one. Throws when cancelled or when the
  /// cache can't say what's missing; otherwise the pass ran to the end.
  @discardableResult
  func fillDocumentDetails(progress: SyncProgressReporter?) async throws -> DetailFillOutcome

  /// Rebuild the cached membership (`query_order`) of the default list and every
  /// saved view from the cheap Tier-0 id projection, so documents that newly
  /// entered a view appear offline. Only ids with a cached `document` row are
  /// added (their detail arrives via R3δ in the same reconcile). No-op unless
  /// *Entire library* is enabled.
  func reconcileSavedViewMembership() async throws

  /// Reachability GC for cached query keys: delete `query_order` / `query_meta`
  /// / `query_sync_error` for every key that is no longer reachable (the default
  /// list, the current saved views, a bounded LRU of recent ad-hoc filters,
  /// anything in use right now), then reclaim the documents those orphans were
  /// pinning. Runs in *both* offline modes — an ad-hoc filter leaves a key
  /// behind either way.
  func collectUnreachableQueries() async throws

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

  @discardableResult
  public func fillDocumentDetails() async throws -> DetailFillOutcome {
    try await fillDocumentDetails(progress: nil)
  }

  public func reconcileDocumentChanges() async throws {
    try await reconcileDocumentChanges(progress: nil)
  }

  /// Reclaim downloaded document files no cached document version references
  /// any more: superseded versions, and documents (or whole servers) the
  /// database has since dropped.
  ///
  /// A protocol extension rather than a requirement: everything it needs is
  /// already on the protocol (`database`), and the blob store is a single
  /// app-group directory, so there is nothing per-backend to implement.
  ///
  /// The reachable set is read across *every* server in one query — the store is
  /// shared, and a per-server answer could not tell a removed server's leftovers
  /// from another server's live files. Callers therefore need not (and must not)
  /// run this once per server.
  @discardableResult
  public func reclaimDocumentContent() async throws -> ContentStore.ReclaimReport {
    // No app-group container (host tests, previews, a mis-configured
    // entitlement) means no blob store to sweep. Not an error: the download
    // path degrades the same way, straight to a temporary file.
    guard let store = try? ContentStore() else { return ContentStore.ReclaimReport() }
    let retained = try await database.retainedContentVersions()
    // Off the main actor: conformers are `@MainActor`, and this walks one
    // directory entry per downloaded document and unlinks files. Detached
    // because that isolation is what we are escaping; the sweep is bounded and
    // idempotent, so not inheriting cancellation costs at most one short pass —
    // and the caller's own `Task.checkCancellation` still sees the cancel.
    return await Task.detached(priority: .utility) {
      store.reclaim(retaining: retained)
    }.value
  }
}

enum CachingRepositoryError: Error {
  /// A pure cache read found nothing for a non-optional resource. The store's
  /// hydrate path tolerates this (cold cache); `sync` then fills it.
  ///
  /// Reachable, despite a note in the offline-stack inventory (#656 item 11)
  /// suggesting otherwise: `currentUser()`, `uiSettings()` and
  /// `serverConfiguration()` all throw it whenever the `ui_settings` /
  /// `server_configuration` singleton has not been synced yet — the ordinary
  /// first-launch state — and `DocumentStore.fillDocumentQuery` reuses it for
  /// "no caching backend at all". Kept.
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

  /// The in-flight writer of each `QueryKey`'s `query_order` — a fill (page 1
  /// included, not only the background continuation) or the membership sweep's
  /// rewrite. Every writer of a key consults this: a new fill drains the current
  /// owner before touching the key, and the membership sweep steps over a key
  /// that is mid-fill. `KeyOwnership` is main-actor isolated like the rest of
  /// this class, and claiming/releasing never suspends, so two writers cannot
  /// both hold a key.
  private let activeFills = KeyOwnership<QueryKey>()

  /// Keys `fillQuery` has been asked for during this repository's lifetime, most
  /// recent last, capped at ``QueryRetentionPolicy/recentAdHocCap``.
  ///
  /// This is what pins *the list on screen*. The persistent LRU cannot: it ranks
  /// on `query_meta.filled_at`, which is only stamped when a fill pages a query
  /// to the *end*, so a list the user is looking at right now over a flaky
  /// connection — the case where losing its cached rows is most visible — has no
  /// stamp at all and would sort last. Bounded because a long session must not
  /// grow this without limit, and the most recent entries are the ones that can
  /// still be on screen.
  private var recentlyRequestedKeys: [QueryKey] = []

  private func noteRequested(_ key: QueryKey) {
    recentlyRequestedKeys.removeAll { $0 == key }
    recentlyRequestedKeys.append(key)
    if recentlyRequestedKeys.count > QueryRetentionPolicy.recentAdHocCap {
      recentlyRequestedKeys.removeFirst(
        recentlyRequestedKeys.count - QueryRetentionPolicy.recentAdHocCap)
    }
  }

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
    // The permission matrix gates the rest, so we don't ask the server for
    // collections the user can't view (doomed 403s). It comes from the cache,
    // which `syncUISettings` — called by the session immediately before this —
    // has just refreshed. When it is unavailable (that fetch failed and nothing
    // was cached), `gate` is nil and we fetch everything, relying on the
    // per-resource 403/401-skip in `syncCollection` as a fallback.
    let gate = try? await database.uiSettings(serverID: serverID)?.permissions
    func canView(_ resource: UserPermissions.Resource) -> Bool {
      gate?.test(.view, for: resource) ?? true
    }

    // Each collection reconciles in its own transaction, and they now run
    // genuinely concurrently rather than serialized behind the main actor.
    // That is the point, and it is safe: no invariant spans two collections,
    // and each `replaceElements` is a whole-set replace for one server.
    //
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
  public func fillQuery(filter: FilterState, category: TransferCategory) async throws
    -> QueryFillHandle
  {
    let key = QueryKey(serverID: serverID, filter: filter)
    // Pin the key before the first suspension: from here until the sweep next
    // reconsiders it, this key counts as in use even if its fill never lands a
    // single page (offline on open).
    noteRequested(key)

    let pageSize = Endpoint.defaultDocumentPageSize
    let database = database
    let serverID = serverID

    // Page 1 is still awaited by the caller (first window on screen + the exact
    // total for the count pill) but is written from inside the fill's own task,
    // so the key has a single owner from its very first write. Written from the
    // caller's context it was unclaimed until the background task existed, and
    // the membership sweep's whole-key `replaceQueryOrder` could land in that
    // gap — after which the fill appended page 2 onto a different ordering.
    // Detached tasks inherit no task-local, so re-establish the caller's
    // category here rather than reading the (default) ambient one.
    let (firstPage, pageOne) = AsyncThrowingStream<UInt?, any Error>.makeStream()

    // Two fills on one key used to interleave: the newcomer's page-1
    // `replaceAll: true` deletes every `query_order` row for the key, and the
    // older fill then keeps appending from its own position counter, leaving a
    // hole only a later full fill repairs. Neither write errors — the primary
    // key is ON CONFLICT REPLACE and the unique key ON CONFLICT IGNORE — so
    // nothing notices. Routine rather than hypothetical since the foreground
    // library fill started paging `[(nil, .default)] + savedViews`, the very
    // keys an open list is filling.
    //
    // So the fill takes the key over: `takeOver` cancels whatever owns it and
    // awaits it actually stopping (cancellation is cooperative — a fill only
    // checks between pages), *until nobody does*, then registers this fill
    // without suspending in between. Draining just once was not enough: a
    // second fill for the key, waiting on the same owner, resumed after the
    // first had claimed and replaced it without stopping it (#735).
    //
    // If *we* are cancelled while waiting there — the user switched away from
    // this request — `takeOver` throws instead of claiming. That matters here
    // specifically: the fill we would start is one the cancellation handler
    // below stops the moment it exists, so taking the key over would cancel a
    // live sibling fill for nothing and leave the key with no refresh at all.
    let task = try await activeFills.takeOver(key) {
      let source = try wrapped.documents(filter: filter)
      return Task.detached(priority: .utility) {
        try await NetworkTransfer.$category.withValue(category) {
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
          //
          // The pages and this stamp are separate transactions, which is safe
          // because `activeFills` makes this fill the key's sole writer for the
          // whole run: another fill drains us first, and the membership sweep
          // steps over an owned key.
          try await database.markQueryFillComplete(queryKey: key, serverID: serverID)
        }
      }
    }

    Task { [weak self] in
      do {
        try await task.value
      } catch is CancellationError {
        // A newer fill drained us, or the view went away. Expected.
      } catch {
        // `fillLibrary` awaits the fill and reports its failure where the user
        // can see it. The interactive path doesn't await the background paging
        // at all, so without this its failures would be entirely silent.
        // Classified rather than a flat `.error`: a list opened offline pages
        // into a dead network, which is routine (see `SyncFailureClass`).
        Logger.sync.log(
          level: SyncFailureClass(error).logLevel(), "Background query fill failed: \(error)")
      }
      // Retract only our own registration: a newer fill may have drained and
      // replaced us while this was waiting.
      self?.activeFills.release(key, ifOwnedBy: task)
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

  /// Whether a fill (or the membership sweep's own rewrite) currently owns this
  /// key's `query_order`.
  private func isFilling(_ key: QueryKey) -> Bool { activeFills.isOwned(key) }

  public func waitForQueryWriters(_ key: QueryKey) async {
    while let owner = activeFills.owner(of: key), !Task.isCancelled {
      // The owner's outcome is its own caller's to report; this only waits.
      _ = try? await owner.value
      // A finished owner is retracted by a separate main-actor job (its
      // registration task, a taking-over fill's `takeOver`, or a sweep's
      // `defer`), which may not have run yet. When `takeOver` is the one that
      // retracts it, the successor registers in that same job, so the takeover
      // does not read as "nobody". Back off briefly rather than spin on the
      // stale entry.
      if activeFills.owner(of: key) == owner {
        try? await Task.sleep(for: .milliseconds(20))
      }
    }
  }

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
    // Whether every view that failed did so because the device is offline. A
    // pass like that is the network, not the library, and says so at `.info`.
    var failedOnlyOffline = true
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
        let handle = try await fillQuery(filter: filter, category: .fill)
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
          failedOnlyOffline = false
          continue
        }
        try? await database.clearQuerySyncError(serverID: serverID, queryKey: key.rawValue)
        succeeded += 1
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        // A rejected view (e.g. an advanced full-text query the server won't run)
        // must not block the *whole* library's coverage.
        Logger.sync.log(
          level: SyncFailureClass(error).logLevel(),
          "Library fill: '\(name ?? "default", privacy: .public)' failed (\(error)); skipping")
        if await recordViewFailure(error, key: key, name: name) {
          failedOnlyOffline = false
        }
      }
    }

    // A completed pass, not a flawless one: one permanently failing view would
    // otherwise pin "last full sync" at Never. But a pass where *nothing*
    // succeeded cached nothing, and stamping it would suppress retries for
    // `LibraryCoverage.maxAge` while the screen claims a fresh sync over an
    // empty cache — the ordinary shape of Wi-Fi with the server unreachable,
    // since neither `isExpensive` nor `isConstrained` means reachable.
    guard succeeded > 0 else {
      Logger.sync.log(
        level: failedOnlyOffline ? .info : .error,
        "Library fill: all \(views.count, privacy: .public) views failed; leaving coverage unset")
      return
    }
    try? await database.setLibraryCoverageAt(Date(), serverID: serverID)
  }

  @discardableResult
  public func fillDocumentDetails(progress: SyncProgressReporter?) async throws
    -> DetailFillOutcome
  {
    guard offlineBrowsingMode == .entireLibrary else { return .complete }
    // Before the seed and the two "what's missing" reads: they're quick, but a
    // gap here shows up as the activity flicking back to "Idle".
    progress?(SyncActivity(stage: .detailFill))

    // Free step: every zero-note document gets an empty notes row from the list
    // payload's count — no request — so it renders "no notes" offline and drops
    // out of the fetch set below.
    let seeded = (try? await database.seedEmptyNotesForZeroCountDocuments(serverID: serverID)) ?? 0

    // Then fetch only what's genuinely missing. One failure (or going offline
    // mid-pass) doesn't abort the rest; whatever failed is still missing, so
    // the next pass tries it again.
    var fetchedMetadata = 0
    var fetchedNotes = 0
    var failure: (any Error)?
    var failed = 0
    defer { progress?(nil) }

    // Notes are a separate resource with their own permission. Without this the
    // fill asks for every noted document's `/notes/` and takes a 403 each time —
    // one doomed request per document, on every foreground, forever. `nil` (no
    // cached matrix yet) stays optimistic, matching `syncElements`.
    let permissions = try? await database.uiSettings(serverID: serverID)?.permissions
    let canViewNotes = permissions?.test(.view, for: .note) ?? true

    let downgraded = try await NetworkTransfer.$category.withValue(.fill) { () -> Bool in
      // These throw: an empty list read as "nothing missing" would clear the
      // detail fill's sync error.
      let missingMetadata = try await database.documentIDsMissingFileMetadata(serverID: serverID)
      let needsNotes =
        canViewNotes ? try await database.documentIDsNeedingNotesFetch(serverID: serverID) : []

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

      // A downgrade mid-pass means the rest is no longer wanted, and
      // `reclaimAfterDowngrade` runs right behind us.
      @MainActor func leftEntireLibrary() -> Bool {
        guard done.isMultiple(of: DetailFillPolicy.downgradeCheckStride) else { return false }
        return offlineBrowsingMode != .entireLibrary
      }

      @MainActor func absorb(_ error: any Error) {
        failed += 1
        failure = SyncFailureClass.firstSurfaced(failure, error)
      }

      for id in missingMetadata {
        try Task.checkCancellation()
        if leftEntireLibrary() { return true }
        do {
          _ = try await metadata(documentId: id)
          fetchedMetadata += 1
        } catch {
          absorb(error)
        }
        done += 1
        reportThrottled()
      }

      for id in needsNotes {
        try Task.checkCancellation()
        if leftEntireLibrary() { return true }
        do {
          _ = try await notes(documentId: id)
          fetchedNotes += 1
        } catch {
          absorb(error)
        }
        done += 1
        reportThrottled()
      }
      return false
    }

    Logger.sync.info(
      "Detail fill: seeded \(seeded, privacy: .public) empty-notes rows, fetched \(fetchedNotes, privacy: .public) notes, \(fetchedMetadata, privacy: .public) metadata, \(failed, privacy: .public) failed"
    )
    if downgraded {
      Logger.sync.info("Detail fill: mode left Entire library mid-pass; stopping")
      return .complete
    }
    return DetailFillOutcome(failure: failure, failed: failed)
  }

  /// Record a saved view's failure for the Offline & Sync screen, unless the
  /// device is offline: that says nothing about the view. An error the view
  /// already has stays until it next syncs. Returns whether it was recorded.
  @discardableResult
  private func recordViewFailure(_ error: any Error, key: QueryKey, name: String?) async -> Bool {
    guard SyncFailureClass(error) != .offline else { return false }
    try? await database.recordQuerySyncError(
      serverID: serverID, queryKey: key.rawValue, savedViewName: name,
      message: Self.syncFailureMessage(error))
    return true
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
      // Routine (see `SyncFailureClass`): a collection this user may not see.
      // Anything else propagates and fails the element phase, which
      // `ServerSession` logs and records at the level the rule gives it.
      Logger.sync.info(
        "Skipping \(R.databaseTableName, privacy: .public) sync: \(error)")
    }
  }

  /// Fetch the UI settings singleton and write it through to the cache.
  ///
  /// Throws without logging: the session records and logs the failure at
  /// `.uiSettings`. Not fatal — `syncElements` carries on from the last cached
  /// permission matrix.
  public func syncUISettings() async throws {
    let settings = try await wrapped.uiSettings()
    try await database.setUISettings(settings, serverID: serverID)
  }

  private func syncServerConfiguration() async throws {
    do {
      let config = try await wrapped.serverConfiguration()
      try await database.setServerConfiguration(config, serverID: serverID)
    } catch let error where Self.isSkippable(error) {
      // Routine, as in `syncCollection`.
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

  // MARK: - Write-through shield

  /// Run a cache write that follows an *already committed* remote mutation, on
  /// a task of its own so the caller's cancellation cannot abandon it.
  ///
  /// The mutation methods here are pessimistic: they forward to the server and
  /// write through only once it has accepted the change. The blocking accessors
  /// these replaced always ran to completion, and that is what the pattern
  /// silently depended on. The `async` accessors are cancellation-aware — GRDB
  /// throws `CancellationError` if the task is cancelled before the access
  /// starts, and interrupts one already running — which is right for a sweep
  /// and wrong here: a caller cancelled in the window between the two (a
  /// dismissed sheet, a view that went away, a server switch) would leave the
  /// server changed and the cache holding the old value, with nothing scheduled
  /// to reconcile the two. A delete is the worst case — the row stays cached,
  /// keeps appearing in lists and is served offline as though it still existed,
  /// until the next `reconcileDocumentDeletions` happens to notice.
  ///
  /// An unstructured `Task` inherits actor isolation but *not* cancellation, so
  /// the write runs to completion; awaiting its value keeps the method's
  /// contract (it still returns only once the cache agrees with the server) and
  /// still propagates a genuine write failure to the caller.
  ///
  /// Only for writes behind a committed remote mutation. Reads and sweep writes
  /// stay cancellable: stopping those loses work, not consistency.
  private func commitCache(
    _ operation: String, _ body: @escaping @Sendable () async throws -> Void
  ) async throws {
    do {
      try await Task { try await body() }.value
    } catch {
      // The caller sees this as a plain failure; only the log can say that the
      // server already accepted the change and it is the cache that is behind.
      Logger.shared.error(
        "Cache write '\(operation, privacy: .public)' failed after the server accepted the change; the cache is stale until the next reconcile: \(error)"
      )
      throw error
    }
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
    try await commitCache("create(tag:)") { [database, serverID] in
      try await database.upsertElement(created, of: TagRecord.self, serverID: serverID)
    }
    return created
  }

  public func update(tag: Tag) async throws -> Tag {
    let updated = try await wrapped.update(tag: tag)
    try await commitCache("update(tag:)") { [database, serverID] in
      try await database.upsertElement(updated, of: TagRecord.self, serverID: serverID)
    }
    return updated
  }

  public func delete(tag: Tag) async throws {
    try await wrapped.delete(tag: tag)
    try await commitCache("delete(tag:)") { [database, serverID, id = tag.id] in
      try await database.deleteElement(TagRecord.self, serverID: serverID, id: id)
    }
  }

  public func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
    let created = try await wrapped.create(correspondent: correspondent)
    try await commitCache("create(correspondent:)") { [database, serverID] in
      try await database.upsertElement(created, of: CorrespondentRecord.self, serverID: serverID)
    }
    return created
  }

  public func update(correspondent: Correspondent) async throws -> Correspondent {
    let updated = try await wrapped.update(correspondent: correspondent)
    try await commitCache("update(correspondent:)") { [database, serverID] in
      try await database.upsertElement(updated, of: CorrespondentRecord.self, serverID: serverID)
    }
    return updated
  }

  public func delete(correspondent: Correspondent) async throws {
    try await wrapped.delete(correspondent: correspondent)
    try await commitCache("delete(correspondent:)") { [database, serverID, id = correspondent.id] in
      try await database.deleteElement(CorrespondentRecord.self, serverID: serverID, id: id)
    }
  }

  public func create(documentType: ProtoDocumentType) async throws -> DocumentType {
    let created = try await wrapped.create(documentType: documentType)
    try await commitCache("create(documentType:)") { [database, serverID] in
      try await database.upsertElement(created, of: DocumentTypeRecord.self, serverID: serverID)
    }
    return created
  }

  public func update(documentType: DocumentType) async throws -> DocumentType {
    let updated = try await wrapped.update(documentType: documentType)
    try await commitCache("update(documentType:)") { [database, serverID] in
      try await database.upsertElement(updated, of: DocumentTypeRecord.self, serverID: serverID)
    }
    return updated
  }

  public func delete(documentType: DocumentType) async throws {
    try await wrapped.delete(documentType: documentType)
    try await commitCache("delete(documentType:)") { [database, serverID, id = documentType.id] in
      try await database.deleteElement(DocumentTypeRecord.self, serverID: serverID, id: id)
    }
  }

  public func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
    let created = try await wrapped.create(storagePath: storagePath)
    try await commitCache("create(storagePath:)") { [database, serverID] in
      try await database.upsertElement(created, of: StoragePathRecord.self, serverID: serverID)
    }
    return created
  }

  public func update(storagePath: StoragePath) async throws -> StoragePath {
    let updated = try await wrapped.update(storagePath: storagePath)
    try await commitCache("update(storagePath:)") { [database, serverID] in
      try await database.upsertElement(updated, of: StoragePathRecord.self, serverID: serverID)
    }
    return updated
  }

  public func delete(storagePath: StoragePath) async throws {
    try await wrapped.delete(storagePath: storagePath)
    try await commitCache("delete(storagePath:)") { [database, serverID, id = storagePath.id] in
      try await database.deleteElement(StoragePathRecord.self, serverID: serverID, id: id)
    }
  }

  public func create(savedView: ProtoSavedView) async throws -> SavedView {
    let created = try await wrapped.create(savedView: savedView)
    try await commitCache("create(savedView:)") { [database, serverID] in
      try await database.upsertElement(created, of: SavedViewRecord.self, serverID: serverID)
    }
    return created
  }

  public func update(savedView: SavedView) async throws -> SavedView {
    let updated = try await wrapped.update(savedView: savedView)
    try await commitCache("update(savedView:)") { [database, serverID] in
      try await database.upsertElement(updated, of: SavedViewRecord.self, serverID: serverID)
    }
    return updated
  }

  public func delete(savedView: SavedView) async throws {
    try await wrapped.delete(savedView: savedView)
    try await commitCache("delete(savedView:)") { [database, serverID, id = savedView.id] in
      try await database.deleteElement(SavedViewRecord.self, serverID: serverID, id: id)
    }
  }

  // MARK: - Documents (pessimistic write-through + cache fallback)

  public func update(document: Document) async throws -> Document {
    let updated = try await wrapped.update(document: document)
    // Write the confirmed object through; the join observation repaints the row
    // in place. `update` is fetched with `full_perms` (see ApiRepository) so the
    // response carries permissions/custom fields — a `.full` write replaces the
    // row completely without dropping them. Ordering under the active sort isn't
    // recomputed offline — mark affected queries stale.
    //
    // Both writes are shielded together: the stale-marking is what tells the
    // list its cached ordering no longer reflects the edit, so landing the row
    // without it is its own kind of divergence. Two transactions rather than
    // one, and deliberately so: anything that can land between them either
    // rebuilds the affected key's order (a fill page, which clears the flag it
    // has just earned the right to clear) or removes the document from it (a
    // delete reconcile, after which there is nothing left to mark). Neither
    // leaves a wrong state behind.
    try await commitCache("update(document:)") { [database, serverID] in
      try await database.upsertDocument(updated, serverID: serverID)
      try await database.markQueriesOrderStale(containing: updated.id, serverID: serverID)
    }
    return updated
  }

  public func delete(document: Document) async throws {
    try await wrapped.delete(document: document)
    // Explicitly prunes every cached query_order referencing it too — no FK
    // cascade does this (dropped in migration V6).
    try await commitCache("delete(document:)") { [database, serverID, id = document.id] in
      try await database.deleteDocuments(serverID: serverID, removedIDs: [id])
    }
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
        Logger.shared.log(
          level: SyncFailureClass(error).readFallbackLogLevel,
          "document(id:) network failed (\(error)); serving cached")
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
        Logger.shared.log(
          level: SyncFailureClass(error).readFallbackLogLevel,
          "document(asn:) network failed (\(error)); serving cached")
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

    guard let watermark = try await deltaWatermark() else {
      // First run: establish the baseline from the newest doc; subsequent passes
      // delta against it. (Avoids re-paging the whole library on cold start.)
      var newestFirst = FilterState.empty
      newestFirst.sortField = .modified
      newestFirst.sortOrder = .descending
      let baseline = try wrapped.documents(filter: newestFirst)
      if let newest = try await baseline.fetch(limit: 1).first?.modified {
        try await setDeltaWatermark(newest)
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
      //
      // `localIDs` is a snapshot taken before the paging began, so a document
      // cached mid-pass is skipped here even though the cursor moves past it.
      // Harmless: whatever cached it did so by fetching it from the network,
      // which is strictly fresher than this delta page's copy of it.
      let toUpsert = entireLibrary ? changed : changed.filter { localIDs.contains($0.id) }
      if !toUpsert.isEmpty {
        Logger.sync.info(
          "Reconcile: refreshing \(toUpsert.count, privacy: .public) changed documents")
        // Note edits bump `modified`, so a changed doc's cached notes may be
        // stale. Dropping them is cheap and local — the upsert refreshes each
        // doc's `notesCount`, so the next `fillDocumentDetails` re-seeds an
        // empty row for free when the count is 0, or re-fetches when it's > 0.
        // We can't tell a note change from any other field change, so this may
        // re-fetch a few docs whose notes didn't actually change.
        //
        // One transaction: a `createNote` / `deleteNote` write-through landing
        // between an upsert and a separate invalidation would be deleted by it,
        // and under *Recently browsed* nothing repairs that until the document
        // is fetched online again.
        //
        // The same write marks stale every cached list whose order a changed
        // document may no longer fit (see `Database.applyChangedDocuments` for
        // the rule). It doesn't claim those keys: the mark touches no
        // `query_order` row, so a fill paging one of them keeps writing, and
        // the mark outlives the fill's remaining pages. What clears it is a
        // rewrite of the whole order from the server — the membership sweep
        // right behind this pass (*Entire library*: the default list and saved
        // views), or the next fill of the list, which every open of it starts.
        let marked = try await database.applyChangedDocuments(toUpsert, serverID: serverID)
        if marked > 0 {
          Logger.sync.info(
            "Reconcile: \(marked, privacy: .public) cached list(s) may be out of order")
        }
        applied += toUpsert.count
      }
      // Commit the cursor per page rather than once at the end — this is what
      // makes an interrupted pass resume instead of restart. A separate
      // transaction from the page's write, and harmlessly so: losing it only
      // re-applies the page next time, and the upsert is a straight replace.
      if cursor > watermark {
        try await setDeltaWatermark(cursor)
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
        guard try await replaceQueryOrderOwningKey(key, orderedIDs: ids) else {
          Logger.sync.info(
            "Membership sweep: '\(name ?? "default", privacy: .public)' was taken over mid-write; skipping"
          )
          continue
        }
        try? await database.clearQuerySyncError(serverID: serverID, queryKey: key.rawValue)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        Logger.sync.log(
          level: SyncFailureClass(error).logLevel(),
          "Membership sweep: '\(name ?? "default", privacy: .public)' failed (\(error)); continuing"
        )
        await recordViewFailure(error, key: key, name: name)
      }
      // Both branches above end on a `try?`, which swallows cancellation along
      // with everything else. On any view but the last, the check at the top of
      // the next iteration catches that; on the last view the loop simply ends
      // and this method returns normally, so `ServerSession.runReconcile` counts
      // a cancelled sweep as one that succeeded. Ask once more here, after the
      // body, so the last view is not a special case.
      //
      // `ServerSession`'s `sweep` helper re-asks the same question before it
      // records an outcome; that is the backstop for this whole family of
      // one-`await`-too-late windows, not a reason to leave them open.
      try Task.checkCancellation()
    }
  }

  /// Rewrite `key`'s membership while *owning* the key, and report whether the
  /// rewrite stood.
  ///
  /// The two `isFilling` guards around the caller used to be enough on their
  /// own, because the write was a blocking main-actor call: nothing could claim
  /// the key between the last check and the committed rewrite. Now that the
  /// write suspends, that window is real — a fill could start inside it and
  /// interleave its page-1 `replaceAll` with this delete-all-and-reinsert,
  /// producing exactly the garbled merge the guards exist to prevent. Claiming
  /// the key for the duration closes it again: a fill starting meanwhile drains
  /// this write (`KeyOwnership.takeOver`) instead of racing it, and the drained sweep leaves
  /// the key to the fill, which writes the better ordering anyway.
  ///
  /// - Returns: `false` if a fill took the key over, so the caller skips the
  ///   view rather than clearing its recorded sync error.
  private func replaceQueryOrderOwningKey(
    _ key: QueryKey, orderedIDs: [UInt]
  ) async throws -> Bool {
    let database = database
    let serverID = serverID
    // `withOwnership` runs the write on an unstructured task — which is what
    // lets it own the key — and so separates the two cancellations: a fill
    // draining us (the write's, reported as `false`) from this sweep being
    // cancelled (ours, thrown). Unasked, the latter would clear the view's
    // recorded sync error and — on the last view — the loop would simply run
    // out, so `ServerSession` would count a cancelled membership sweep as a
    // completed one and advance its freshness stamps on the strength of it.
    return try await activeFills.withOwnership(of: [key]) {
      try await database.replaceQueryOrder(
        queryKey: key, serverID: serverID, orderedIDs: orderedIDs)
    }
  }

  /// Apply the *Recently browsed* storage cap: cut every list not viewed within
  /// ``QueryRetentionPolicy/recentlyBrowsedGrace`` back to its first
  /// `OfflineLibrarySize.recentlyBrowsedDefaultListCap` rows, and drop the
  /// documents that frees.
  ///
  /// Only correct while none of this server's lists can be on screen or filling
  /// (see `Database.capRecentlyBrowsedQueries`), so ``ServerSession`` runs it as
  /// part of its first repository build, which every list waits for.
  ///
  /// The list the app opens with is exempt: the default list, and the filter the
  /// document list restores from last time, which is what actually opens when
  /// one was left applied. That list opens as soon as the store has a
  /// repository, and every open refills it in full, so cutting it here would
  /// only cost a download online and lose rows offline.
  ///
  /// Soft-fail: a missed pass leaves the cache as it was until the next launch.
  func applyRecentlyBrowsedCap() async {
    // The accessor re-checks the mode; this only skips a pointless write.
    guard offlineBrowsingMode == .recentlyBrowsed else { return }
    let cutoff = Date().addingTimeInterval(-QueryRetentionPolicy.recentlyBrowsedGrace)
    let opening: Set<QueryKey> = [
      QueryKey(serverID: serverID, filter: .default),
      QueryKey(serverID: serverID, filter: FilterModel.restoredFilterState()),
    ]
    do {
      let result = try await database.capRecentlyBrowsedQueries(
        serverID: serverID,
        keepingFirst: OfflineLibrarySize.recentlyBrowsedDefaultListCap,
        notViewedSince: cutoff,
        exempting: opening)
      if result.truncatedRows > 0 {
        Logger.sync.info(
          "Recently browsed cap: trimmed \(result.truncatedRows, privacy: .public) row(s), reclaimed \(result.removedDocuments, privacy: .public) document(s) for server \(self.serverLogLabel, privacy: .public)"
        )
      }
    } catch {
      Logger.sync.error(
        "Recently browsed cap failed for server \(self.serverLogLabel, privacy: .public): \(error)"
      )
    }
  }

  public func collectUnreachableQueries() async throws {
    // Deliberately not gated on `offlineBrowsingMode`: `fillQuery` writes a
    // key's rows on every list open in either mode, so orphans accumulate in
    // either mode — under *Recently browsed* they are in fact the *only* thing
    // keeping the reclaimed library from growing back one abandoned filter at a
    // time.
    let savedViews = try await database.elements(SavedViewRecord.self, serverID: serverID)
    let cached = try await database.cachedQueries(serverID: serverID)

    // No suspension from here to the claim below — that is what makes the
    // in-use guarantee hold. `activeFills` and `recentlyRequestedKeys` are
    // main-actor state read *after* the last `await`, so a fill that started
    // during either read above is already in one of them, and a fill that starts
    // after the claim has to drain this sweep (`takeOver`) before it writes.
    var reachable: Set<QueryKey> = [QueryKey(serverID: serverID, filter: .default)]
    for view in savedViews {
      reachable.insert(QueryKey(serverID: serverID, filter: FilterState(savedView: view)))
    }
    reachable.formUnion(activeFills.ownedKeys)
    reachable.formUnion(recentlyRequestedKeys)
    // The LRU ranks *last*, over what is not already pinned. Ranking the whole
    // cached set would let the default list and the saved views — reachable for
    // their own reasons, whatever their fill stamps say — spend the slots the
    // cap exists to reserve for ad-hoc filters: twenty recently filled saved
    // views would otherwise leave ad-hoc retention at zero.
    let adHocCandidates = cached.filter { !reachable.contains($0.key) }
    reachable.formUnion(
      QueryRetention.mostRecentlyFilled(
        adHocCandidates, limit: QueryRetentionPolicy.recentAdHocCap))

    let collected = Set(cached.map(\.key).filter { !reachable.contains($0) })
    guard !collected.isEmpty else { return }

    let database = database
    let serverID = serverID
    // Deleting *these* keys, not everything outside `reachable`: a fill for a
    // key that was never cached — so absent from `collected`, so not owned in
    // `activeFills` below and under no obligation to drain this sweep — can
    // commit its page-one rows while the sweep is pending. A `NOT IN (reachable)`
    // delete would take those fresh rows with it and leave the fill appending
    // page two at a nonzero position, i.e. a permanently truncated cached list.
    // Keys that went unreachable since the snapshot are collected next pass.
    let collecting = collected
    // Own every key being collected for the duration of the delete, exactly as
    // `replaceQueryOrderOwningKey` owns the one key it rewrites. A `fillQuery`
    // arriving for one of them now cancels and *awaits* this sweep before its
    // page-1 write, instead of racing it and having its fresh rows deleted from
    // under it. A cancelled sweep throws out of here rather than returning as a
    // clean pass — see `replaceQueryOrderOwningKey` for why that is asked
    // separately from the delete being drained.
    let completed = try await activeFills.withOwnership(of: collected) {
      _ = try await database.pruneQueries(serverID: serverID, collectedKeys: collecting)
    }
    guard completed else {
      // A fill took one of the collected keys over. The rest are still garbage
      // and the next sweep collects them.
      Logger.sync.info("Reachability sweep drained by a fill; retrying next pass")
      return
    }

    Logger.sync.info(
      "Reachability sweep: collected \(collected.count, privacy: .public) orphaned query key(s) for server \(self.serverLogLabel, privacy: .public)"
    )
    // Only when something was actually collected: this is the anti-join that
    // orphaned keys were blocking, and running it on every reconcile regardless
    // would scan the whole document table to find nothing — and would widen the
    // blast radius of "referenced means `query_order` membership" (a document
    // cached by an ASN scan and listed nowhere) to every sweep rather than the
    // passes that just freed something.
    let reclaimed = try await database.pruneUnreferencedDocuments(serverID: serverID)
    if reclaimed > 0 {
      Logger.sync.info(
        "Reachability sweep: reclaimed \(reclaimed, privacy: .public) unreferenced document(s)")
    }
  }

  /// Per-server delta watermark (newest `modified` applied), in
  /// `server_sync_state` keyed by serverID. Regenerable sync state —
  /// `clearCache` resets it, and an *absent* row just re-baselines on the next
  /// pass.
  ///
  /// An *unreadable* row is a different thing entirely and must not be reported
  /// as absent: the caller reads `nil` as "first run" and re-baselines from the
  /// newest document, which moves the cursor past every change the real
  /// watermark had not applied yet — and a high-water mark only moves up, so
  /// those documents are unreachable forever. So the failure propagates: the
  /// pass ends without touching the cursor and `ServerSession`'s sweep records
  /// it, leaving the stored watermark intact for the next attempt.
  private func deltaWatermark() async throws -> Date? {
    try await database.deltaWatermark(serverID: serverID)
  }

  /// Commit the cursor, swallowing an ordinary persistence failure (the pass
  /// re-applies the page next time) but *not* a cancellation.
  ///
  /// This is the delta's last `await` on its final page: `isExhausted` doesn't
  /// throw, and under *Recently browsed* the membership sweep behind it no-ops,
  /// so a swallowed cancellation here would let `reconcileDocumentChanges`
  /// return normally with the cursor uncommitted — and `ServerSession` would
  /// stamp the pass as clean over a delta that never landed.
  private func setDeltaWatermark(_ date: Date) async throws {
    do {
      try await database.setDeltaWatermark(date, serverID: serverID)
    } catch is CancellationError {
      throw CancellationError()
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
        Logger.shared.log(
          level: SyncFailureClass(error).readFallbackLogLevel,
          "metadata(documentId:) network failed (\(error)); serving cached")
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
        Logger.shared.log(
          level: SyncFailureClass(error).readFallbackLogLevel,
          "notes(documentId:) network failed (\(error)); serving cached")
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
    try await commitCache("createNote(documentId:)") { [database, serverID] in
      try await database.setNotes(updated, serverID: serverID, documentID: documentId)
    }
    return updated
  }

  public func deleteNote(id: UInt, documentId: UInt) async throws -> [Document.Note] {
    let updated = try await wrapped.deleteNote(id: id, documentId: documentId)
    try await commitCache("deleteNote(id:documentId:)") { [database, serverID] in
      try await database.setNotes(updated, serverID: serverID, documentID: documentId)
    }
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
    //
    // `updateUISettings` does the read, the merge and the write in a single
    // transaction: split across two accessors, an element sync writing a
    // freshly-fetched row in between would be overwritten by a merge built on
    // the pre-sync user and permission matrix. `commitCache` covers the other
    // half — cancelled here, the server would be holding settings the cached
    // singleton denies.
    try await commitCache("update(settings:)") { [database, serverID] in
      try await database.updateUISettings(serverID: serverID) { current in
        UISettings(user: current.user, settings: settings, permissions: current.permissions)
      }
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

  public nonisolated var imageSessionDelegate: (any URLSessionDelegate)? {
    wrapped.imageSessionDelegate
  }

  public func supports(feature: BackendFeature) -> Bool {
    wrapped.supports(feature: feature)
  }
}
