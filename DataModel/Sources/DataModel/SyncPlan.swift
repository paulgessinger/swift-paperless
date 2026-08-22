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

  /// The ordered set of actions for a sweep of every **inactive** server.
  ///
  /// - The active server is excluded (it is driven by `DocumentStore`, never by
  ///   the engine — this is what prevents a two-instance double-fill race).
  /// - Uncredentialed servers always yield a `needsAuthOnly` action (cheap,
  ///   throttle-exempt, so a freshly-arrived token is picked up on the very next
  ///   sweep).
  /// - Credentialed servers are dropped while their last successful sweep is
  ///   still within `throttle`; otherwise they yield a sync action whose
  ///   `runHeavyFill` is gated on `isEntireLibrary &&` that server's own
  ///   ``SyncCondition/allowsProactiveSync`` — each server's own
  ///   `syncOverCellular` opt-in applies to *that* server only, not the whole
  ///   sweep.
  /// - Ordering is stable (by `id`) for deterministic, testable behavior.
  public static func inactiveActions(
    connections: [ServerSnapshot],
    activeID: UUID?,
    lastSweep: [UUID: Date],
    now: Date,
    throttle: TimeInterval,
    isExpensive: Bool,
    isConstrained: Bool
  ) -> [SyncServerAction] {
    connections
      .filter { $0.id != activeID }
      .sorted { $0.id.uuidString < $1.id.uuidString }
      .compactMap { server in
        guard server.hasToken else {
          // Uncredentialed: mark needs-auth every sweep (no network, no throttle).
          return SyncServerAction(serverID: server.id, needsAuthOnly: true, runHeavyFill: false)
        }
        if let last = lastSweep[server.id], now.timeIntervalSince(last) < throttle {
          return nil  // still fresh — skip the network sweep
        }
        let condition = SyncCondition(
          isExpensive: isExpensive, isConstrained: isConstrained,
          syncOverCellular: server.syncOverCellular)
        return SyncServerAction(
          serverID: server.id,
          needsAuthOnly: false,
          runHeavyFill: condition.allowsProactiveSync && server.isEntireLibrary)
      }
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
