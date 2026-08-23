//
//  ServerSession.swift
//  AppShared
//
//  One configured server's networking life: its `CachingRepository`, its
//  in-flight sync, and the freshness stamp the scheduler throttles on.
//
//  This type exists to make the invariant **"at most one `CachingRepository`
//  per server executes at any time"** structural. Previously that was upheld by
//  convention: `DocumentStore` drove the active server, `SyncEngine` swept the
//  rest and skipped `activeConnectionId` to stay out of its way. Two independent
//  owners, coordinating through a key that mutates underneath them — which is
//  exactly how a server that went active mid-sweep could end up driven twice.
//  With one session per server, the coordination scope (`CachingRepository`'s
//  per-instance `activeFills`) and the ownership scope finally coincide.
//
//  The session is an imperative shell only. Every *decision* — which servers to
//  sync, in what order, whether the throttle has elapsed, whether a heavy fill
//  is allowed on this link — stays in the pure, unit-tested `DataModel.SyncPlan`,
//  because `AppShared` has no test target and anything moved in here stops being
//  covered.
//

import Common
import DataModel
import Foundation
import Networking
import Persistence
import os

@MainActor
@Observable
public final class ServerSession {
  /// Where this server stands. `needsAuth` is a *state*, not a branch in the
  /// scheduler: a config-synced-but-uncredentialed server is a normal session
  /// that simply has nothing it can do yet, and picks up the moment a token
  /// lands.
  public enum State: Equatable, Sendable {
    /// No repository built yet (nothing has asked this server to do anything).
    case idle
    /// Repository built; the server is usable.
    case ready
    /// No usable credential. No network call is attempted.
    case needsAuth
    /// The last attempt failed (offline, rejected token, …). Retried on the
    /// next trigger; the stamp is not advanced, so the throttle won't hide it.
    case failed
  }

  /// Where this session's repository comes from.
  private enum Source {
    /// Production: assembled from the server's stored connection through
    /// ``makeCachingRepository``, and rebuilt whenever that connection changes.
    case stored(database: Database, manager: ConnectionManager, mode: ApiRepository.Mode)
    /// Previews and tests: handed in ready-made, and never rebuilt. This is what
    /// keeps "every store is driven by a session" true without dragging a
    /// `ConnectionManager` and a real connection record into a fixture — the
    /// alternative being a `DocumentStore.init(repository:)` escape hatch that
    /// would let production code bypass a server's owner too.
    case fixed(any Repository & CachingBackend)
  }

  public let serverID: UUID

  @ObservationIgnored private let source: Source

  /// The retained stack, together with the `Connection` it was assembled from.
  /// Only ever populated for ``Source/stored``.
  ///
  /// Retaining it is the point — a long-lived repository is what lets
  /// `activeFills` dedupe across sweeps instead of only within one. But the
  /// per-sweep rebuild it replaces picked up connection edits for free, so the
  /// `Connection` is kept alongside and compared on each use: a changed URL,
  /// token, identity or extra header rebuilds the stack. (`Connection` is
  /// `Equatable` over exactly the fields `makeCachingRepository` consumes.)
  ///
  /// This comparison is load-bearing for re-auth, and only works because
  /// `StoredConnection.token` reads the Keychain *live* on every access: a
  /// re-auth writes the new token to the Keychain without changing the
  /// `StoredConnection` record at all, so a session that compared records rather
  /// than `Connection`s would keep serving the rejected token forever. The same
  /// holds for `ConnectionsView.updateExtraHeaders`, which edits headers in
  /// place.
  @ObservationIgnored private var built:
    (connection: Connection, repository: any Repository & CachingBackend)?

  /// The build currently in flight, if any.
  ///
  /// `prepareRepository` has an `await` between "is `built` still good?" and
  /// committing the answer, so without this two callers could both miss the
  /// check and each construct a repository — one of which would be handed to
  /// its caller while the *other* sat in `built`. Two live repositories for one
  /// server is precisely the state this type exists to make unrepresentable,
  /// and deleting the engine's active-server guard is what made the race
  /// reachable: a sweep and an `activate` can now land on the same session.
  @ObservationIgnored private var building:
    (connection: Connection, task: Task<any Repository & CachingBackend, Error>)?

  // In-flight work, one single-flight per phase.
  //
  // Per *phase* rather than one per session, because the two callers want
  // different things: the store drives phases individually (pull-to-refresh
  // wants the element sync back, not a full server sweep), while the scheduler
  // runs the composed sequence. Sharing the per-phase tasks is what lets both
  // callers hit the same session concurrently and coalesce — which in turn is
  // what let the engine's "skip the active server" guard go away, since there
  // is no longer a second owner to stay out of the way of.
  //
  // The slots stay unobserved — `deinit` cancels them, and an observed
  // property can't be read from a nonisolated deinit — so `didSet` mirrors
  // them into ``isSyncing`` instead. Doing it in `didSet` rather than at each
  // mutation site is what keeps the flag from drifting: there is no assignment
  // that can forget to update it.
  @ObservationIgnored private var syncTask: Task<Void, Never>? {
    didSet { refreshIsSyncing() }
  }
  @ObservationIgnored private var elementSyncTask: Task<Void, Error>? {
    didSet { refreshIsSyncing() }
  }
  @ObservationIgnored private var reconcileTask: Task<ReconcileResult, Never>? {
    didSet { refreshIsSyncing() }
  }
  @ObservationIgnored private var libraryFillTask: Task<Bool, Never>? {
    didSet { refreshIsSyncing() }
  }
  @ObservationIgnored private var detailFillTask: Task<Bool, Never>? {
    didSet { refreshIsSyncing() }
  }

  /// Whether any work is running for this server.
  ///
  /// Tracks the task slots rather than ``syncActivities``, because the activity
  /// list is a *progress* channel and answers a different question. It is
  /// legitimately empty between phases, and while a phase is in flight but has
  /// not yet reported its first checkpoint — the element sync clears its stage
  /// the moment it finishes, and the reconcile that follows is kicked detached,
  /// so there is a window in every pass where work is plainly running and
  /// nothing is being reported. Gating a control on "no stage is reporting"
  /// made the Offline & Sync screen's Sync now button flick back to enabled
  /// mid-pass.
  public private(set) var isSyncing: Bool = false

  private func refreshIsSyncing() {
    let busy =
      syncTask != nil || elementSyncTask != nil || reconcileTask != nil
      || libraryFillTask != nil || detailFillTask != nil
    if busy != isSyncing {
      isSyncing = busy
    }
  }

  public private(set) var state: State = .idle

  /// Last *fully* successful pass. The scheduler's throttle input; advanced only
  /// on a clean pass, so an interrupted or partially-failed one retries on the
  /// next trigger rather than being throttled away.
  public private(set) var lastSuccessfulSync: Date?

  /// When the reconcile last *ran*. Advances on every attempt, deliberately —
  /// it gates the sub-throttle below, and a server that fails every sweep must
  /// not refetch its whole live id set on each of the seventeen on-appear
  /// triggers. Distinct from ``lastReconcileSuccess`` for exactly that reason.
  @ObservationIgnored private var lastReconcileAttempt: Date?

  /// When the reconcile last refreshed *something*. The user-facing "last
  /// refreshed" stamp the Offline & Sync screen renders, so it is observed.
  public private(set) var lastReconcileSuccess: Date?

  /// Keeps the active server's on-appear triggers off the wire. Bypassed by
  /// pull-to-refresh and by the scheduler, which has already applied its own
  /// (much longer) throttle before asking.
  @ObservationIgnored private let reconcileThrottle: TimeInterval = 300

  /// Every sync stage running right now *for this server*, in a fixed order;
  /// empty when idle. The Offline & Sync screen renders the active server's,
  /// through its store.
  ///
  /// A list rather than one "current" stage because they genuinely overlap: the
  /// store's `sync()` starts the reconcile in its own task and returns, so a
  /// reconcile is usually still running when the library fill begins. Publishing
  /// one of them meant whichever finished first blanked the screen to "Idle"
  /// while the other carried on — and, because progress is reported coarsely, it
  /// stayed blank until the survivor reached its next checkpoint.
  ///
  /// Living on the session rather than the store is what makes an *inactive*
  /// server's progress observable at all: the engine's sweeps used to report
  /// nowhere, because the only reporter belonged to the active server's store.
  public private(set) var syncActivities: [SyncActivity] = []

  // One entry per sweep currently running. Keyed by stage because each sweep
  // owns exactly one, and because a sweep reporting "done" says only *that* —
  // it can't say which stage it was, so the key has to come from the call site.
  @ObservationIgnored
  private var activeStages: [SyncActivity.Stage: SyncActivity] = [:]

  /// Fold one sweep's progress into the published activity. `nil` retires the
  /// stage; the list keeps showing whatever else is still running.
  private func report(_ activity: SyncActivity?, for stage: SyncActivity.Stage) {
    activeStages[stage] = activity
    syncActivities = activeStages.values.sortedForDisplay
  }

  public init(
    serverID: UUID,
    database: Database,
    manager: ConnectionManager,
    mode: ApiRepository.Mode = Bundle.main.appConfiguration.mode
  ) {
    self.serverID = serverID
    source = .stored(database: database, manager: manager, mode: mode)
  }

  /// A session around a repository that already exists, for previews and tests.
  /// It consults no connection record and never rebuilds: the repository it is
  /// handed is the one it keeps, so it is `.ready` from birth.
  public init(serverID: UUID, repository: any Repository & CachingBackend) {
    self.serverID = serverID
    source = .fixed(repository)
    state = .ready
  }

  deinit {
    syncTask?.cancel()
    elementSyncTask?.cancel()
    reconcileTask?.cancel()
    libraryFillTask?.cancel()
    detailFillTask?.cancel()
  }

  // MARK: - Repository access

  /// The live repository, or `nil` before anything has built it.
  private var current: (any Repository & CachingBackend)? {
    switch source {
    case .fixed(let repository): repository
    case .stored: built?.repository
    }
  }

  /// The server's repository, or `nil` before anything has built it.
  public var repository: (any Repository)? { current }

  /// The same instance seen as the cache-backed surface the sync sequence and
  /// the store's projections both drive.
  public var backend: (any CachingBackend)? { current }

  /// Build the stack, or hand back the retained one when it still matches
  /// `stored`. Assembly goes through ``makeCachingRepository`` so every server's
  /// layering is identical to the app shell's.
  ///
  /// Public because activating a store on this server has to *await* the build:
  /// the store publishes `repository` straight off the session, so a lazy build
  /// would leave it on `NullRepository` — projection detached — for the first
  /// render after every switch.
  @discardableResult
  public func prepareRepository(
    for stored: StoredConnection
  ) async throws -> any Repository & CachingBackend {
    switch source {
    case .fixed(let repository):
      return repository
    case .stored(let database, let manager, let mode):
      // At most one build in flight per session. A caller that arrives while
      // one is running waits for it and then re-evaluates, rather than starting
      // a second: it usually finds `built` already matching — the same
      // connection, so it gets the winner's repository for free — and otherwise
      // builds the next one itself against config read *after* the wait, so a
      // re-auth that landed mid-build isn't overwritten by a stale result.
      //
      // The failure of someone else's build is not this caller's to inherit;
      // it just means the slot is free and this caller tries for itself.
      while let building {
        _ = try? await building.task.value
        if self.building?.task == building.task {
          self.building = nil
        }
      }

      let connection = try stored.connection
      if let built, built.connection == connection {
        return built.repository
      }
      if built != nil {
        Logger.sync.info(
          "Server \(stored.logLabel, privacy: .public) connection changed; rebuilding stack")
        // Everything still running belongs to the *outgoing* repository: the
        // phase tasks captured it by value when they started, so they would go
        // on writing through a stack built from credentials the server has
        // since rejected — and, worse, a follow-up `sync()` would *join* that
        // stale element task and report success without ever exercising the new
        // token. (`ConnectionsView.updateExtraHeaders` and re-auth both land
        // here.) The store used to cancel this on every repository swap; that
        // guard was doing two jobs and only the server-switch half became
        // unnecessary when sessions took ownership — a rebuild is the same
        // session, so this half still has to be done by hand.
        retirePhases()
      }
      // No suspension between the loop exiting and this assignment, and the
      // session is main-actor, so the slot cannot be claimed twice.
      let task = Task { @MainActor () throws -> any Repository & CachingBackend in
        try await makeCachingRepository(
          for: stored, database: database, manager: manager, mode: mode)
      }
      building = (connection, task)
      defer {
        if building?.task == task {
          building = nil
        }
      }
      let repository = try await task.value
      built = (connection, repository)
      return repository
    }
  }

  /// Cancel and clear every phase slot, leaving the composed ``sync`` slot
  /// alone.
  ///
  /// Deliberately not the composed slot: `runSync` calls `prepareRepository`
  /// *before* its own phases, so a rebuild discovered there would otherwise
  /// cancel the very task doing the discovering. Retiring the phases is enough
  /// — the composed pass then sees them fail out and ends on its own.
  private func retirePhases() {
    elementSyncTask?.cancel()
    elementSyncTask = nil
    reconcileTask?.cancel()
    reconcileTask = nil
    libraryFillTask?.cancel()
    libraryFillTask = nil
    detailFillTask?.cancel()
    detailFillTask = nil
  }

  /// Drop the retained stack. Used when the server row goes away — the row
  /// delete FK-cascades the cache, so there is nothing else to clean up.
  public func invalidate() {
    syncTask?.cancel()
    syncTask = nil
    retirePhases()
    built = nil
    state = .idle
  }

  // MARK: - Phases

  /// Run (or join) this server's element sync.
  ///
  /// Unthrottled by design: every on-appear trigger expects this to reach the
  /// network, and the single-flight — not a timer — is what keeps the launch
  /// flurry to one pass. Rethrows to *every* joined caller, so a user-initiated
  /// pull-to-refresh that lands on an in-flight background sync still sees the
  /// failure it needs to toast.
  public func syncElements() async throws {
    if let elementSyncTask {
      Logger.sync.debug("Joining in-flight element sync")
      return try await elementSyncTask.value
    }
    guard let backend = current else {
      // No repository yet (e.g. a store still on `NullRepository` before login).
      Logger.sync.info("Element sync skipped: session has no repository")
      return
    }
    Logger.sync.debug("Starting element sync")
    let task = Task { [weak self] in
      try await NetworkTransfer.$category.withValue(.sync) {
        try await backend.syncElements { self?.report($0, for: .elementSync) }
      }
    }
    elementSyncTask = task
    defer {
      // Retract only our own task: a replacement may already own the slot by the
      // time we resume, and clearing it blindly would break its coalescing.
      if elementSyncTask == task {
        elementSyncTask = nil
      }
    }
    try await task.value
  }

  /// What one reconcile pass achieved.
  ///
  /// Two stamps ask two different questions of the same pass — the scheduler
  /// wants "fully clean" before it advances a throttle that could hide a broken
  /// server for fifteen minutes; the Offline & Sync screen wants "did anything
  /// refresh", because one flaky sweep shouldn't erase the two that worked. One
  /// pass, both answers.
  public struct ReconcileResult: Sendable {
    public var succeeded = 0
    public var failed = false
    public var cancelled = false

    /// Neither failed nor called off. Only a clean pass advances the scheduler's
    /// freshness stamp.
    public var isClean: Bool { !failed && !cancelled }
  }

  /// Throttled remote-delete reconcile: drop cached documents that no longer
  /// exist on the server, fold in the changed-metadata delta, then rebuild
  /// saved-view membership. Soft-fail throughout. `force` bypasses the 300 s
  /// sub-throttle.
  @discardableResult
  public func reconcileDocuments(force: Bool = false) async -> ReconcileResult {
    if let reconcileTask {
      return await reconcileTask.value
    }
    guard let backend = current else { return ReconcileResult() }
    if !force, let last = lastReconcileAttempt,
      Date().timeIntervalSince(last) < reconcileThrottle
    {
      return ReconcileResult()
    }
    lastReconcileAttempt = Date()
    let task = Task { @MainActor [weak self] in
      guard let self else { return ReconcileResult() }
      return await runReconcile(backend: backend)
    }
    reconcileTask = task
    let result = await task.value
    if reconcileTask == task {
      reconcileTask = nil
    }
    return result
  }

  private func runReconcile(backend: any CachingBackend) async -> ReconcileResult {
    report(SyncActivity(stage: .reconcile), for: .reconcile)
    defer { report(nil, for: .reconcile) }

    // Each sweep carries its own catch. The delete sweep is the most
    // failure-prone of the three — it fetches the server's entire live id set —
    // and under one shared `do` its failure took the freshness delta *and* the
    // membership rebuild down with it, so a single flaky request cost the whole
    // reconcile. Cancellation is the exception: it means the pass as a whole is
    // unwanted, so it stops the remaining sweeps instead of being stepped over.
    var result = ReconcileResult()
    func sweep(_ label: String, _ body: () async throws -> Void) async {
      guard !result.cancelled else { return }
      do {
        try await body()
        result.succeeded += 1
      } catch {
        guard !error.isCancellationError else {
          Logger.sync.debug("Reconcile cancelled during \(label, privacy: .public)")
          result.cancelled = true
          return
        }
        Logger.sync.info(
          "Reconcile sweep \(label, privacy: .public) failed (suppressed): \(error)")
        result.failed = true
      }
    }

    // Deletes first (correctness), then the changed-metadata delta (freshness),
    // then the saved-view membership sweep (so newly-matched docs — now landed
    // at detail by the delta — appear in every offline list). The last two are
    // no-ops unless *Entire library* is enabled.
    await NetworkTransfer.$category.withValue(.reconcile) {
      await sweep("deletions") { try await backend.reconcileDocumentDeletions() }
      await sweep("changes") {
        try await backend.reconcileDocumentChanges { [weak self] in
          // The delta finishing doesn't end the reconcile — the membership
          // sweep runs after it — so fall back to the bare stage.
          self?.report($0 ?? SyncActivity(stage: .reconcile), for: .reconcile)
        }
      }
      await sweep("membership") { try await backend.reconcileSavedViewMembership() }
    }

    // A pass in which *something* refreshed counts. A cancelled pass stamps
    // nothing — it didn't finish, it was called off.
    if result.succeeded > 0, !result.cancelled {
      lastReconcileSuccess = Date()
    }
    return result
  }

  /// Proactive *Entire library* fill, gated by the setting and an unmetered
  /// link. Soft-fail (offline-tolerant). `force` ignores the freshness marker
  /// (e.g. the user just enabled the setting).
  ///
  /// Returns whether the pass finished — `true` also when there was legitimately
  /// nothing to do, `false` only when it errored or was called off. The composed
  /// sequence needs that distinction to decide whether the server is fully
  /// synced; the store's callers discard it.
  @discardableResult
  public func fillLibrary(unmetered: Bool, force: Bool = false) async -> Bool {
    guard unmetered, let backend = current, backend.offlineBrowsingMode == .entireLibrary
    else { return true }

    // Join an in-flight fill rather than starting a second pass over the same
    // queries. `force` is not lost by joining: a fill only runs at all when the
    // coverage marker is stale or forced, so one is already doing the work.
    if let libraryFillTask {
      return await libraryFillTask.value
    }
    let task = Task { @MainActor [weak self] in
      do {
        try await NetworkTransfer.$category.withValue(.fill) {
          try await backend.fillLibrary(force: force) { self?.report($0, for: .libraryFill) }
        }
        return true
      } catch is CancellationError {
        Logger.sync.info("Proactive library fill cancelled")
        return false
      } catch {
        Logger.sync.info("Proactive library fill failed (suppressed): \(error)")
        return false
      }
    }
    libraryFillTask = task
    let completed = await task.value
    if libraryFillTask == task {
      libraryFillTask = nil
    }
    return completed
  }

  /// Proactive *Entire library* per-document detail fill (notes + file
  /// metadata). Run after ``fillLibrary(unmetered:force:)`` so the document rows
  /// to walk are already on disk. Idempotent and resumable (driven off what's
  /// still missing), so it needs no `force`. Soft-fail.
  @discardableResult
  public func fillDocumentDetails(unmetered: Bool) async -> Bool {
    guard unmetered, let backend = current, backend.offlineBrowsingMode == .entireLibrary
    else { return true }
    if let detailFillTask {
      return await detailFillTask.value
    }
    let task = Task { @MainActor [weak self] in
      do {
        try await NetworkTransfer.$category.withValue(.fill) {
          try await backend.fillDocumentDetails { self?.report($0, for: .detailFill) }
        }
        return true
      } catch is CancellationError {
        Logger.sync.info("Proactive detail fill cancelled")
        return false
      } catch {
        Logger.sync.info("Proactive detail fill failed (suppressed): \(error)")
        return false
      }
    }
    detailFillTask = task
    let completed = await task.value
    if detailFillTask == task {
      detailFillTask = nil
    }
    return completed
  }

  // MARK: - Composed sequence

  /// Run (or join) this server's full sync pass.
  ///
  /// The sequence is the one the active path has always run — element sync, the
  /// three reconcile sweeps, then the proactive fills — and is now the only copy
  /// of it. Nothing throws out: a per-server failure (offline, a rethrown 401)
  /// is this server's problem alone and must never affect its siblings.
  ///
  /// `runHeavyFill` is `SyncPlan`'s decision, not this type's.
  public func sync(stored: StoredConnection, runHeavyFill: Bool) async {
    if let syncTask {
      return await syncTask.value
    }
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await runSync(stored: stored, runHeavyFill: runHeavyFill)
    }
    syncTask = task
    await task.value
    // Retract only our own task: a swap can retire this pass mid-flight and a
    // replacement may already own `syncTask` by the time we resume, and clearing
    // it blindly would break the replacement's coalescing.
    if syncTask == task {
      syncTask = nil
    }
  }

  /// Degrade to per-server needs-auth without a network call: deterministic and
  /// cheap, and the next trigger picks the server up once a token lands. The 401
  /// path stays a backstop for a token the server rejects.
  public func markNeedsAuth(_ stored: StoredConnection) {
    guard case .stored(_, let manager, _) = source else { return }
    Logger.sync.info(
      "Server \(stored.logLabel, privacy: .public) uncredentialed; marking needs-auth (no sync)")
    state = .needsAuth
    manager.markNeedsAuth(for: serverID)
  }

  private func runSync(stored: StoredConnection, runHeavyFill: Bool) async {
    Logger.sync.info(
      "Syncing server \(stored.logLabel, privacy: .public) (heavyFill: \(runHeavyFill))")
    do {
      _ = try await prepareRepository(for: stored)
      state = .ready

      // Cheap tier (always, regardless of metered-ness): element sync + the
      // reconcile sweeps (the last two self-gate on *Entire library*).
      try await syncElements()

      // The scheduler applied its own, much longer throttle before asking, so
      // the reconcile's 300 s sub-throttle — which exists to keep the *active*
      // server's on-appear flurry off the wire — must not veto this pass.
      let reconcile = await reconcileDocuments(force: true)

      // Heavy tier: only on an unmetered *Entire library* server (SyncPlan gate).
      var filled = true
      if runHeavyFill, !reconcile.cancelled {
        filled = await fillLibrary(unmetered: true, force: false)
        filled = await fillDocumentDetails(unmetered: true) && filled
      }

      // Advance the stamp only on a *fully* successful pass — a pass that failed
      // or was called off partway retries on the next trigger.
      guard reconcile.isClean, filled else {
        Logger.sync.info(
          "Server \(stored.logLabel, privacy: .public) partially synced; stamp not advanced")
        return
      }
      lastSuccessfulSync = Date()
      Logger.sync.info("Server \(stored.logLabel, privacy: .public) synced")
    } catch {
      // A pass retired by a rebuild (or by the caller going away) was called
      // off, not failed: leaving `state` alone keeps a connection edit from
      // showing the server as broken, and the next trigger picks it up.
      guard !error.isCancellationError else {
        Logger.sync.debug(
          "Sync cancelled for \(stored.logLabel, privacy: .public)")
        return
      }
      state = .failed
      Logger.sync.info(
        "Sync failed for \(stored.logLabel, privacy: .public) (suppressed): \(error)")
    }
  }
}
