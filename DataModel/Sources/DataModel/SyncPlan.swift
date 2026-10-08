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

  /// The work this server should do, already decided: the fill is present only
  /// on an unmetered path for an *Entire library* server. Empty when
  /// `needsAuthOnly` — there is nothing to run without a credential.
  ///
  /// A phase set rather than a "heavy fill?" flag so the executor receives a
  /// *decision* rather than the inputs to one, and so a new kind of work
  /// (document binaries, OCR content, thumbnails) is a new case here rather
  /// than another boolean threaded through every layer.
  public let phases: SyncPhases

  public init(serverID: UUID, needsAuthOnly: Bool, phases: SyncPhases) {
    self.serverID = serverID
    self.needsAuthOnly = needsAuthOnly
    self.phases = phases
  }
}

/// Pure planning for the multi-server sync sweep.
public enum SyncPlan {
  /// A dependency-free snapshot of one configured server, as the engine sees it
  /// at sweep time. `isEntireLibrary` is `AppShared.OfflineBrowsingMode ==
  /// .entireLibrary` flattened to a `Bool` so this stays in `DataModel` (which
  /// does not know `OfflineBrowsingMode`).
  public struct ServerSnapshot: Equatable, Sendable {
    public let id: UUID
    public let hasToken: Bool
    public let isEntireLibrary: Bool
    /// This server's own opt-in to proactive syncing on a metered link — see
    /// ``SyncCondition``.
    public let syncOverCellular: Bool

    public init(id: UUID, hasToken: Bool, isEntireLibrary: Bool, syncOverCellular: Bool) {
      self.id = id
      self.hasToken = hasToken
      self.isEntireLibrary = isEntireLibrary
      self.syncOverCellular = syncOverCellular
    }
  }

  /// Which servers a sweep covers.
  public enum Scope: Equatable, Sendable {
    /// Every server except the active one, which `DocumentStore` drives while
    /// the app is open.
    case excludingActive(UUID?)
    /// Every server, for a background run with no `DocumentStore`.
    case all
  }

  /// The ordered set of actions for a sweep of every **inactive** server.
  /// See ``actions(connections:scope:lastSweep:now:throttle:cost:allowsFill:)``.
  public static func inactiveActions(
    connections: [ServerSnapshot],
    activeID: UUID?,
    lastSweep: [UUID: Date],
    now: Date,
    throttle: TimeInterval,
    cost: LinkCost
  ) -> [SyncServerAction] {
    actions(
      connections: connections, scope: .excludingActive(activeID), lastSweep: lastSweep,
      now: now, throttle: throttle, cost: cost, allowsFill: true)
  }

  /// The ordered set of actions for a sweep of the servers in `scope`.
  ///
  /// - Uncredentialed servers always yield a `needsAuthOnly` action (cheap,
  ///   throttle-exempt, so a freshly-arrived token is picked up on the very next
  ///   sweep).
  /// - Credentialed servers are dropped while their last sweep is still within
  ///   `throttle`; otherwise they yield a sync action whose `.fill` phase is
  ///   gated on `allowsFill`, `isEntireLibrary` and that server's own
  ///   ``SyncCondition/allowsProactiveSync``.
  /// - Stalest first: never-swept servers, then the oldest `lastSweep`, with
  ///   `id` breaking ties. A background run that runs out of time has then
  ///   reached the servers that needed it most.
  public static func actions(
    connections: [ServerSnapshot],
    scope: Scope,
    lastSweep: [UUID: Date],
    now: Date,
    throttle: TimeInterval,
    cost: LinkCost,
    allowsFill: Bool
  ) -> [SyncServerAction] {
    connections
      .filter { server in
        guard case .excludingActive(let activeID) = scope else { return true }
        return server.id != activeID
      }
      .sorted { lhs, rhs in
        switch (lastSweep[lhs.id], lastSweep[rhs.id]) {
        case (nil, .some): true
        case (.some, nil): false
        case (.some(let l), .some(let r)) where l != r: l < r
        default: lhs.id.uuidString < rhs.id.uuidString
        }
      }
      .compactMap { server in
        guard server.hasToken else {
          // Uncredentialed: mark needs-auth every sweep (no network, no throttle).
          return SyncServerAction(serverID: server.id, needsAuthOnly: true, phases: .nothing)
        }
        if let last = lastSweep[server.id], now.timeIntervalSince(last) < throttle {
          return nil  // still fresh — skip the network sweep
        }
        let phases =
          allowsFill
          ? phases(
            isEntireLibrary: server.isEntireLibrary,
            condition: SyncCondition(cost: cost, syncOverCellular: server.syncOverCellular))
          : .cheap
        return SyncServerAction(serverID: server.id, needsAuthOnly: false, phases: phases)
      }
  }

  /// The phases one credentialed server should run.
  ///
  /// Shared by both drivers: the sweep reaches it through ``actions(connections:scope:lastSweep:now:throttle:cost:allowsFill:)``,
  /// and the active server — which `DocumentStore` drives directly, outside any
  /// sweep — calls it itself. One function means the server the user is looking
  /// at cannot drift onto a different rule than its siblings, which is exactly
  /// what a `Bool` computed afresh at each call site invited.
  ///
  /// The mode gate is here as well as in the executor (which re-reads the
  /// server's mode from the database before filling) on purpose: this is the
  /// copy that is unit-tested, and the executor's is a guard, not a decision.
  public static func phases(isEntireLibrary: Bool, condition: SyncCondition) -> SyncPhases {
    condition.allowsProactiveSync && isEntireLibrary ? .full : .cheap
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
