//
//  ReconcileGate.swift
//  DataModel
//

import Foundation

/// Decides when one server's reconcile pass may start.
///
/// Unforced requests (the active server's on-appear triggers) start at most one
/// pass per ``interval``. A forced request always starts one, and so does the
/// first request after ``oweHeal()``.
///
/// The executor is `ServerSession` (in `AppShared`, which has no test target);
/// the decision lives here so it is unit-tested, like ``SyncPlan``.
public struct ReconcileGate: Sendable {
  public let interval: TimeInterval

  /// When a pass last started. Advances on every start, whatever the pass's
  /// outcome, so a server that fails every pass is still throttled.
  public private(set) var lastStart: Date?

  /// Whether a pass is owed that has not started yet: the cache missed a change
  /// the server accepted, and only a pass that starts afterwards reads it.
  public private(set) var isHealOwed = false

  public init(interval: TimeInterval) {
    self.interval = interval
  }

  /// Let the next request start a pass whatever the throttle says.
  ///
  /// A pass already running doesn't settle this: it may have read the server
  /// before the change.
  public mutating func oweHeal() {
    isHealOwed = true
  }

  /// Whether a pass starts now. Starting stamps ``lastStart`` and settles an
  /// owed heal; declining changes nothing.
  public mutating func start(force: Bool, now: Date = Date()) -> Bool {
    if !force, !isHealOwed, let lastStart, now.timeIntervalSince(lastStart) < interval {
      return false
    }
    lastStart = now
    isHealOwed = false
    return true
  }
}
