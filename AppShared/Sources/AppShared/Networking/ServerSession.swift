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

  // In-flight work, one single-flight per phase.
  //
  // Per *phase* rather than one per session, because the two callers want
  // different things: the store drives phases individually (pull-to-refresh
  // wants the element sync back, not a full server sweep), while the scheduler
  // runs the composed sequence. Sharing the per-phase tasks is what lets both
  // callers hit the same session concurrently and coalesce — which in turn is
  // what let the engine's "skip the active server" guard go away, since there
  // is no longer a second owner to stay out of the way of.
  @ObservationIgnored private var syncTask: Task<Void, Never>?
  @ObservationIgnored private var elementSyncTask: Task<Void, Error>?
  @ObservationIgnored private var reconcileTask: Task<ReconcileResult, Never>?
  @ObservationIgnored private var proactiveFillTask: Task<Bool, Never>?

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
    proactiveFillTask?.cancel()
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
      let connection = try stored.connection
      if let built, built.connection == connection {
        return built.repository
      }
      if built != nil {
        Logger.sync.info(
          "Server \(stored.logLabel, privacy: .public) connection changed; rebuilding stack")
      }
      let repository = try await makeCachingRepository(
        for: stored, database: database, manager: manager, mode: mode)
      built = (connection, repository)
      return repository
    }
  }

  /// Drop the retained stack. Used when the server row goes away — the row
  /// delete FK-cascades the cache, so there is nothing else to clean up.
  public func invalidate() {
    syncTask?.cancel()
    syncTask = nil
    elementSyncTask?.cancel()
    elementSyncTask = nil
    reconcileTask?.cancel()
    reconcileTask = nil
    proactiveFillTask?.cancel()
    proactiveFillTask = nil
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
  /// link: the library fill (paging every query), then the per-document detail
  /// fill (notes + file metadata) over whatever the library fill just landed on
  /// disk. Soft-fail (offline-tolerant). `force` ignores the library fill's
  /// freshness marker (e.g. the user just enabled the setting); the detail fill
  /// needs no `force` of its own — it is idempotent and resumable, driven off
  /// what is still missing.
  ///
  /// Single-flighted as *one unit* rather than per stage. Guarding the two
  /// separately let a second caller start a fresh library fill while the first
  /// was still in its detail pass, so two passes over "what's still missing"
  /// each reported their own completed/total into the same stage — read on
  /// screen as the progress count flickering between two unrelated series.
  /// There are five triggers that reach the same server: launch, foreground,
  /// the mode picker, "Sync now", and a background run.
  ///
  /// Returns whether the pass finished — `true` also when there was legitimately
  /// nothing to do, `false` only when it errored or was called off. The composed
  /// sequence needs that distinction to decide whether the server is fully
  /// synced; the store's callers discard it.
  @discardableResult
  public func runProactiveFill(unmetered: Bool, force: Bool = false) async -> Bool {
    guard unmetered, let backend = current, backend.offlineBrowsingMode == .entireLibrary
    else { return true }

    // Join an in-flight pass rather than starting a second one over the same
    // queries. `force` is not lost by joining: a fill only runs at all when the
    // coverage marker is stale or forced, so one is already doing the work.
    if let proactiveFillTask {
      return await proactiveFillTask.value
    }
    let task = Task { @MainActor [weak self] in
      await self?.runFill(backend: backend, force: force) ?? false
    }
    proactiveFillTask = task
    let completed = await task.value
    if proactiveFillTask == task {
      proactiveFillTask = nil
    }
    return completed
  }

  /// Stop the in-flight proactive fill, if any — e.g. the caller is about to
  /// reclaim cache the fill would otherwise keep writing back into (leaving
  /// *Entire library* on this server). A no-op when nothing is running; the
  /// task's own `Task.checkCancellation()` checkpoints (per saved view in
  /// `fillLibrary`, per document in `fillDocumentDetails`) do the rest.
  public func cancelProactiveFill() {
    proactiveFillTask?.cancel()
  }

  private func runFill(backend: any CachingBackend, force: Bool) async -> Bool {
    var completed = true
    do {
      try await NetworkTransfer.$category.withValue(.fill) {
        try await backend.fillLibrary(force: force) { [weak self] in
          self?.report($0, for: .libraryFill)
        }
      }
    } catch is CancellationError {
      // Cancellation means the whole pass is unwanted — don't chase it with a
      // detail fill against a backend nobody is waiting on any more.
      Logger.sync.info("Proactive fill cancelled")
      return false
    } catch {
      Logger.sync.info("Proactive library fill failed (suppressed): \(error)")
      completed = false
    }
    do {
      try await NetworkTransfer.$category.withValue(.fill) {
        try await backend.fillDocumentDetails { [weak self] in
          self?.report($0, for: .detailFill)
        }
      }
    } catch is CancellationError {
      Logger.sync.info("Proactive detail fill cancelled")
      return false
    } catch {
      Logger.sync.info("Proactive detail fill failed (suppressed): \(error)")
      completed = false
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
        filled = await runProactiveFill(unmetered: true, force: false)
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
      state = .failed
      Logger.sync.info(
        "Sync failed for \(stored.logLabel, privacy: .public) (suppressed): \(error)")
    }
  }
}
