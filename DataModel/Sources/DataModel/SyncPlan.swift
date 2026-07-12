//
//  SyncPlan.swift
//  DataModel
//

import Foundation

/// One server's resolved sync intent for a multi-server sweep.
///
/// `SyncPlan` produces these; the imperative `SyncEngine` (in `AppShared`, which
/// has no test target) executes them. Keeping the *decision* here makes the
/// interesting logic — active exclusion, throttle, uncredentialed degrade,
/// heavy-fill gating — unit-testable cross-platform, mirroring how
/// `OfflineLibrarySize` backs `OfflineBrowsingMode.default(forDocumentCount:)`.
public struct SyncServerAction: Equatable, Sendable {
  public let serverID: UUID

  /// The server has no stored credential yet (config-synced-but-uncredentialed,
  /// e.g. a Stage-12 UBKVS `server` row whose iCloud-Keychain token hasn't
  /// arrived). Execute by marking per-server needs-auth and making **no**
  /// network call — never fail the whole engine.
  public let needsAuthOnly: Bool

  /// Run the heavy proactive fill (`fillLibrary` + `fillDocumentDetails`) in
  /// addition to the always-run cheap tier (`syncElements` + reconcile). Only
  /// true on an unmetered path for an *Entire library* server. Implies a token
  /// is present (`needsAuthOnly == false`).
  public let runHeavyFill: Bool

  public init(serverID: UUID, needsAuthOnly: Bool, runHeavyFill: Bool) {
    self.serverID = serverID
    self.needsAuthOnly = needsAuthOnly
    self.runHeavyFill = runHeavyFill
  }
}

/// Pure planning for the multi-server (inactive-server) sync sweep.
public enum SyncPlan {
  /// Which servers a sweep considers.
  public enum SweepScope: Equatable, Sendable {
    /// Exclude the given active server. The foreground case: the active server
    /// is driven by `DocumentStore`, and a second `CachingRepository` instance
    /// must never race it on the same `query_order` rows.
    case excludingActive(UUID?)
    /// Consider every configured server. The headless background case: no
    /// `DocumentStore` exists in the process, so the engine is provably the
    /// only writer and may safely include the active server.
    case all
  }

  /// A dependency-free snapshot of one configured server, as the engine sees it
  /// at sweep time. `isEntireLibrary` is `AppShared.OfflineBrowsingMode ==
  /// .entireLibrary` flattened to a `Bool` so this stays in `DataModel` (which
  /// does not know `OfflineBrowsingMode`).
  public struct ServerSnapshot: Equatable, Sendable {
    public let id: UUID
    public let hasToken: Bool
    public let isEntireLibrary: Bool

    public init(id: UUID, hasToken: Bool, isEntireLibrary: Bool) {
      self.id = id
      self.hasToken = hasToken
      self.isEntireLibrary = isEntireLibrary
    }
  }

  /// The ordered set of actions for one sweep.
  ///
  /// - `scope` decides whether the active server participates (see
  ///   ``SweepScope``).
  /// - Uncredentialed servers always yield a `needsAuthOnly` action (cheap,
  ///   throttle-exempt, so a freshly-arrived token is picked up on the very next
  ///   sweep).
  /// - Credentialed servers are dropped while their last successful sweep is
  ///   still within `throttle`; otherwise they yield a sync action whose
  ///   `runHeavyFill` is gated on `includeHeavy && unmetered && isEntireLibrary`
  ///   (`includeHeavy: false` is the quick-refresh tier: cheap sweep only, no
  ///   proactive fill, regardless of mode or network).
  /// - Ordering is **stalest-first** by `lastSweep` (never-synced first), with a
  ///   stable `id` tie-break — so a time-boxed background run reaches the
  ///   neediest servers before its budget expires.
  public static func sweepActions(
    connections: [ServerSnapshot],
    scope: SweepScope,
    lastSweep: [UUID: Date],
    now: Date,
    throttle: TimeInterval,
    unmetered: Bool,
    includeHeavy: Bool
  ) -> [SyncServerAction] {
    let excluded: UUID? =
      switch scope {
      case .excludingActive(let id): id
      case .all: nil
      }
    return
      connections
      .filter { $0.id != excluded }
      .sorted { lhs, rhs in
        switch (lastSweep[lhs.id], lastSweep[rhs.id]) {
        case (nil, nil): lhs.id.uuidString < rhs.id.uuidString
        case (nil, .some): true
        case (.some, nil): false
        case (.some(let l), .some(let r)): l != r ? l < r : lhs.id.uuidString < rhs.id.uuidString
        }
      }
      .compactMap { server in
        guard server.hasToken else {
          // Uncredentialed: mark needs-auth every sweep (no network, no throttle).
          return SyncServerAction(serverID: server.id, needsAuthOnly: true, runHeavyFill: false)
        }
        if let last = lastSweep[server.id], now.timeIntervalSince(last) < throttle {
          return nil  // still fresh — skip the network sweep
        }
        return SyncServerAction(
          serverID: server.id,
          needsAuthOnly: false,
          runHeavyFill: includeHeavy && unmetered && server.isEntireLibrary)
      }
  }

  /// The foreground sweep: every **inactive** server, full tier. Wrapper over
  /// ``sweepActions(connections:scope:lastSweep:now:throttle:unmetered:includeHeavy:)``.
  public static func inactiveActions(
    connections: [ServerSnapshot],
    activeID: UUID?,
    lastSweep: [UUID: Date],
    now: Date,
    throttle: TimeInterval,
    unmetered: Bool
  ) -> [SyncServerAction] {
    sweepActions(
      connections: connections,
      scope: .excludingActive(activeID),
      lastSweep: lastSweep,
      now: now,
      throttle: throttle,
      unmetered: unmetered,
      includeHeavy: true)
  }

  /// Server IDs that appeared since the last observation tick and warrant an
  /// initial (throttle-exempt) sync. The active server is excluded — it is
  /// synced by `DocumentStore` when it becomes active, so the engine must not
  /// double-drive it even on first appearance.
  public static func newlyAdded(
    current: Set<UUID>, known: Set<UUID>, activeID: UUID?
  ) -> Set<UUID> {
    var added = current.subtracting(known)
    if let activeID {
      added.remove(activeID)
    }
    return added
  }
}
