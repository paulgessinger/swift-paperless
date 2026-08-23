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

  /// In-flight sync, so concurrent callers coalesce onto one pass rather than
  /// running a second one against the same server.
  @ObservationIgnored private var syncTask: Task<Void, Never>?

  public private(set) var state: State = .idle

  /// Last *fully* successful pass. The scheduler's throttle input; advanced only
  /// on a clean pass, so an interrupted or partially-failed one retries on the
  /// next trigger rather than being throttled away.
  public private(set) var lastSuccessfulSync: Date?

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
    built = nil
    state = .idle
  }

  // MARK: - Sync

  /// Run (or join) this server's sync pass.
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
      let backend = try await prepareRepository(for: stored)
      state = .ready

      // Cheap tier (always, regardless of metered-ness): element sync + the
      // reconcile sweeps (the last two self-gate on *Entire library*).
      try await NetworkTransfer.$category.withValue(.sync) {
        try await backend.syncElements()
      }

      // Each reconcile sweep carries its own catch: the deletion sweep is the
      // most failure-prone of the three — it fetches the server's entire live id
      // set — and under one shared `try` its failure took the freshness delta,
      // the membership rebuild *and* the heavy fill down with it. Cancellation is
      // the exception: it means the pass as a whole is unwanted, so it stops the
      // remaining sweeps instead of being logged and stepped over.
      var failed = false
      var cancelled = false
      func sweep(_ label: String, _ body: () async throws -> Void) async {
        guard !cancelled else { return }
        do {
          try await body()
        } catch {
          guard !error.isCancellationError else {
            Logger.sync.debug("Reconcile cancelled during \(label, privacy: .public)")
            cancelled = true
            return
          }
          Logger.sync.info(
            "Reconcile sweep \(label, privacy: .public) failed (suppressed): \(error)")
          failed = true
        }
      }
      await NetworkTransfer.$category.withValue(.reconcile) {
        await sweep("deletions") { try await backend.reconcileDocumentDeletions() }
        await sweep("changes") { try await backend.reconcileDocumentChanges() }
        await sweep("membership") { try await backend.reconcileSavedViewMembership() }
      }

      // Heavy tier: only on an unmetered *Entire library* server (SyncPlan gate).
      if runHeavyFill, !cancelled {
        try await NetworkTransfer.$category.withValue(.fill) {
          try await backend.fillLibrary(force: false)
          try await backend.fillDocumentDetails()
        }
      }

      // Advance the stamp only on a *fully* successful pass — a pass that failed
      // or was called off partway retries on the next trigger.
      guard !failed, !cancelled else {
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
