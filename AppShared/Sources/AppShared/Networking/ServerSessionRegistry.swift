//
//  ServerSessionRegistry.swift
//  AppShared
//
//  Owns exactly one ``ServerSession`` per configured server, for the lifetime of
//  that server's row.
//
//  Session *lifetime* and sync *scheduling* are different jobs, and keeping them
//  in one type is what let `SyncEngine` grow into an owner as well as a
//  scheduler. The registry answers "which servers exist, and what is each one's
//  session"; `SyncEngine` answers "which of them should sync now, in what
//  order". Neither needs the other's state.
//
//  The registry is the **sole** observer of `manager.connections` for session
//  lifecycle. It has to be: it maintains a second map keyed by the same UUIDs,
//  and two independent observers of the same table would drift apart exactly the
//  way the previous two repository owners did.
//
//  `ConnectionManager` deliberately stays *below* this type — `NeedsAuthRepository`
//  already depends on it, so a registry-aware `ConnectionManager` would close a
//  dependency cycle.
//

import Common
import DataModel
import Foundation
import Networking
import Persistence
import os

@MainActor
@Observable
public final class ServerSessionRegistry {
  @ObservationIgnored private let database: Database
  @ObservationIgnored private let manager: ConnectionManager
  @ObservationIgnored private let mode: ApiRepository.Mode

  /// One session per known server. Observable so a screen can show every
  /// server's state, not just the active one's.
  public private(set) var sessions: [UUID: ServerSession] = [:]

  /// Server IDs seen at the last observation tick, diffed to spot additions and
  /// removals.
  @ObservationIgnored private var knownServerIDs: Set<UUID> = []
  @ObservationIgnored private var observationTask: Task<Void, Never>?

  /// Called after each observation tick with the current set and the set as it
  /// was before, so a scheduler can decide what a newly-appeared server deserves.
  ///
  /// The registry deliberately does not make that decision itself: whether a new
  /// server is synced immediately, and whether the active one is excluded, is
  /// `SyncPlan`'s call, not lifecycle.
  @ObservationIgnored
  public var onServersChanged: (@MainActor (_ current: Set<UUID>, _ previous: Set<UUID>) -> Void)?

  public init(
    database: Database,
    manager: ConnectionManager,
    mode: ApiRepository.Mode = Bundle.main.appConfiguration.mode
  ) {
    self.database = database
    self.manager = manager
    self.mode = mode
  }

  deinit {
    observationTask?.cancel()
  }

  // MARK: - Lifecycle

  /// Begin observing the `server` table (via `manager.connections`, its sole
  /// projection), creating and dropping sessions as rows come and go.
  ///
  /// Wired to the *observation* rather than the "Add server" UI action, so a
  /// Stage-12 UBKVS `server` upsert flows through the same path for free.
  public func start() {
    guard observationTask == nil else { return }
    // Seed with the current set so the first tick reports no spurious additions;
    // servers present at launch are handled by the caller's explicit sweep.
    knownServerIDs = Set(manager.connections.keys)
    observationTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        withObservationTracking {
          _ = self?.manager.connections.keys
        } onChange: {
          continuation.yield()
          continuation.finish()
        }
        self?.handleConnectionsChanged()
        for await _ in stream { break }
      }
    }
  }

  private func handleConnectionsChanged() {
    let current = Set(manager.connections.keys)
    let previous = knownServerIDs
    // A vanished row has already FK-cascaded its whole cache, so there is no
    // cache work here — just stop and release the session.
    for id in previous.subtracting(current) {
      sessions.removeValue(forKey: id)?.invalidate()
      Logger.sync.info("Server row removed; dropped its session")
    }
    knownServerIDs = current
    onServersChanged?(current, previous)
  }

  // MARK: - Access

  /// The server's session, created on first request.
  ///
  /// Creation is cheap: a session assembles no repository until something
  /// actually asks it to sync, so holding one per configured server costs
  /// nothing for servers that stay idle.
  public func session(for id: UUID) -> ServerSession {
    if let existing = sessions[id] {
      return existing
    }
    let session = ServerSession(serverID: id, database: database, mode: mode)
    sessions[id] = session
    return session
  }

  /// Every session's last fully-successful sync, for the scheduler's throttle.
  /// Servers that have never completed a pass are absent rather than distant-past.
  public func lastSuccessfulSyncs() -> [UUID: Date] {
    sessions.compactMapValues(\.lastSuccessfulSync)
  }
}
