//
//  SyncFailure.swift
//  Networking
//
//  How the offline/sync stack treats a failure: what level it logs at, and
//  whether the Offline & Sync screen shows it.
//
//  Every failure path in that stack used to log at `.info`, which the unified
//  log does not persist by default — so a user's exported logs, read at the
//  default level, showed no sync failure at all, and nothing on screen did
//  either (#663). The rule, applied everywhere a sync/fill/reconcile failure is
//  caught:
//
//  | class         | what it is                                 | log (sync)                  | surfaced |
//  |---------------|--------------------------------------------|-----------------------------|----------|
//  | `cancelled`   | the caller went away; nothing failed       | `.debug`                    | no       |
//  | `routine`     | 401/403 (401 already flips needs-auth)     | `.info`                     | no       |
//  | `offline`     | the device has no network                  | `.info`                     | no       |
//  | `unreachable` | device online, server didn't answer        | `.notice`; `.error` if 3+   | yes      |
//  | `degraded`    | 5xx, bad payload, TLS, version, local I/O  | `.error`                    | yes      |
//
//  Offline is the case the offline cache exists for, so it must never read as
//  an error — neither in the log nor on screen. An unreachable server might be
//  a blip (a dropped connection, a phone switching networks), so a single
//  occurrence stays at `.notice`, which is still persisted and exported; only a
//  run of them escalates. A degradation is a real problem on the first go.
//
//  Pure and in `Networking` (not `AppShared`, which has no test target) because
//  the whole point is that the rule stays one rule; see `SyncFailureTest`.
//

import Common
import DataModel
import Foundation
import os

/// The classification of one failure in the sync stack. See the table at the
/// top of this file.
public enum SyncFailureClass: Sendable, Equatable {
  case cancelled
  case routine
  case offline
  case unreachable
  case degraded

  /// How many consecutive failures of one site it takes before an unreachable
  /// server logs at `.error`. Three: the foreground triggers alone produce a
  /// couple of attempts in quick succession, so two could still be one blip.
  public static let unreachableEscalation = 3

  public init(_ error: any Error) {
    if error.isCancellationError {
      self = .cancelled
      return
    }
    if error is any ResourceForbiddenError {
      self = .routine
      return
    }
    if let request = error as? RequestError {
      switch request {
      case .forbidden, .unauthorized:
        self = .routine
      case .connectivity(_, let kind, _):
        self = kind == .offline ? .offline : .unreachable
      default:
        self = .degraded
      }
      return
    }
    // A transport failure that never went through a repository's
    // normalization. No path status to consult here, so the code decides alone —
    // which still gets the device-side codes right.
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain, let code = NSURLError(rawValue: nsError.code),
      let kind = TransportFailureKind(code: code, path: .unknown)
    {
      self = kind == .offline ? .offline : .unreachable
      return
    }
    self = .degraded
  }

  /// Whether the Offline & Sync screen should list this failure.
  public var isSurfaced: Bool {
    switch self {
    case .unreachable, .degraded: true
    case .cancelled, .routine, .offline: false
    }
  }

  /// The level a failed sync phase logs at, given how many times in a row
  /// (this one included) the same site has now failed.
  public func logLevel(consecutiveFailures: Int = 1) -> OSLogType {
    switch self {
    case .cancelled: .debug
    case .routine, .offline: .info
    case .unreachable:
      consecutiveFailures >= Self.unreachableEscalation ? .error : .default
    case .degraded: .error
    }
  }

  /// Of the failure a phase is already holding and one it has just absorbed,
  /// the one it should report — `nil` while nothing worth surfacing has
  /// happened.
  ///
  /// For the phases that keep going past a failed *item* (the per-document
  /// detail fill above all): they end up having seen many errors and can report
  /// at most one, and must report none at all when nothing among them was
  /// surfaced. That last part is what keeps "you're offline" off the Offline &
  /// Sync screen when the network drops in the middle of a long pass — every
  /// remaining item fails, and none of those failures says anything about the
  /// server.
  ///
  /// First-wins among the surfaced ones: the first failure is the one closest
  /// to the cause, and the ones after it are usually its fallout (the network
  /// going away, a server that has started refusing everything).
  public static func firstSurfaced(_ held: (any Error)?, _ error: any Error) -> (any Error)? {
    if let held { return held }
    return SyncFailureClass(error).isSurfaced ? error : nil
  }

  /// The level for a *read* that failed on the network and was answered from
  /// the cache instead.
  ///
  /// Lower than ``logLevel(consecutiveFailures:)``: the user got their data, so
  /// this is the offline cache working rather than failing. Only a server that
  /// answered wrongly is worth a persisted line — the next sync of the same
  /// server will report it properly if it keeps happening.
  public var readFallbackLogLevel: OSLogType {
    switch self {
    case .cancelled: .debug
    case .routine, .offline, .unreachable: .info
    case .degraded: .default
    }
  }
}

/// A part of a server's sync pass that can fail on its own. Each is tracked
/// separately so one part succeeding clears only its own failure.
///
/// Declaration order is display order.
public enum SyncFailureSite: String, Sendable, Hashable, CaseIterable {
  /// Assembling the server's repository stack (connection, credentials).
  case connection
  /// The permissions / UI settings singleton. Its failure doesn't abort the
  /// element sync (it falls back to the cached matrix), so without its own site
  /// it would never be seen.
  case uiSettings
  /// The element collections and the server configuration, as one phase.
  case elements
  /// Reconcile: dropping documents deleted on the server.
  case deletions
  /// Reconcile: the changed-metadata delta.
  case changes
  /// Reconcile: saved-view membership.
  case membership
  /// Reconcile: collecting query keys nothing reaches any more.
  case reachability
  /// *Entire library*: the proactive list fill, as a whole. (Individual views
  /// that fail are reported per view, through `query_sync_error`.)
  case libraryFill
  /// *Entire library*: the per-document notes / file metadata fill.
  case detailFill
}

/// One server's record of which parts of its sync last failed, and how.
///
/// Every site follows the same rule: a surfaced failure (see
/// ``SyncFailureClass/isSurfaced``) records or updates its entry; a success
/// clears it; anything else — offline, a 401/403, a cancellation — leaves the
/// entry exactly as it was, because it says nothing new about whether that part
/// of the sync works. That is what keeps "you're offline" off the screen
/// without hiding a real failure that happened before the network went away.
public struct SyncFailureLedger: Sendable, Equatable {
  public struct Entry: Sendable, Equatable, Identifiable {
    public var id: SyncFailureSite { site }
    public var site: SyncFailureSite
    public var failureClass: SyncFailureClass
    /// A short, user-facing reason.
    public var message: String
    /// When it last failed.
    public var failedAt: Date
    /// How many attempts in a row have failed, this one included.
    public var consecutiveFailures: Int

    public init(
      site: SyncFailureSite, failureClass: SyncFailureClass, message: String, failedAt: Date,
      consecutiveFailures: Int
    ) {
      self.site = site
      self.failureClass = failureClass
      self.message = message
      self.failedAt = failedAt
      self.consecutiveFailures = consecutiveFailures
    }
  }

  /// What recording a failure decided, for the caller's log line.
  public struct Outcome: Sendable, Equatable {
    public var failureClass: SyncFailureClass
    public var logLevel: OSLogType
    /// Including this one; `0` for a failure that isn't counted (not surfaced).
    public var consecutiveFailures: Int
  }

  private var entries: [SyncFailureSite: Entry] = [:]

  public init() {}

  /// Every current failure, in ``SyncFailureSite`` order.
  public var current: [Entry] {
    SyncFailureSite.allCases.compactMap { entries[$0] }
  }

  public var isEmpty: Bool { entries.isEmpty }

  public subscript(site: SyncFailureSite) -> Entry? { entries[site] }

  /// Record that `site` failed with `error`.
  ///
  /// `message` is an autoclosure because building it (a localized description)
  /// is wasted work for the failures that aren't recorded.
  @discardableResult
  public mutating func recordFailure(
    _ error: any Error, at site: SyncFailureSite, message: @autoclosure () -> String,
    now: Date = Date()
  ) -> Outcome {
    let failureClass = SyncFailureClass(error)
    guard failureClass.isSurfaced else {
      return Outcome(
        failureClass: failureClass, logLevel: failureClass.logLevel(), consecutiveFailures: 0)
    }
    let consecutive = (entries[site]?.consecutiveFailures ?? 0) + 1
    entries[site] = Entry(
      site: site, failureClass: failureClass, message: message(), failedAt: now,
      consecutiveFailures: consecutive)
    return Outcome(
      failureClass: failureClass,
      logLevel: failureClass.logLevel(consecutiveFailures: consecutive),
      consecutiveFailures: consecutive)
  }

  /// Record that `site` completed. Returns whether that cleared a failure, so
  /// the caller can log the recovery.
  @discardableResult
  public mutating func recordSuccess(at site: SyncFailureSite) -> Bool {
    entries.removeValue(forKey: site) != nil
  }

  /// Forget everything — the server's stack was rebuilt from a changed
  /// connection, so what failed against the old one says nothing about the new.
  public mutating func reset() {
    entries = [:]
  }
}
