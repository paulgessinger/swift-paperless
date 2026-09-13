//
//  TransportFailure.swift
//  Networking
//
//  Best-effort classification of a transport failure: is the *device* offline,
//  or is the device fine and the *server* unreachable? The two need different
//  things from the user ("turn on Wi-Fi" vs. "your server is down, or the
//  address is wrong"), but URLSession's error code alone can't always tell them
//  apart — a request made with no network at all can fail as
//  `cannotFindHost` just as well as one against a mistyped hostname. Combining
//  the code with the network path status *at the moment of failure* can.
//
//  The classification is pure and lives here so it can be tested on the host.
//  The path status comes from the app (`NetworkMonitor`, in AppShared) through
//  `NetworkPathProbe`.
//

import Common
import Foundation
import os

/// The device's network path status, as `NWPathMonitor` reports it.
public enum NetworkPathStatus: Sendable, Equatable {
  /// The device has a usable network interface.
  case satisfied
  /// The device has no usable network interface.
  case unsatisfied
  /// Nobody reported a status: no monitor is installed (the share extension,
  /// host-side tests), or it hasn't delivered its first path yet.
  case unknown
}

/// Process-wide source of the current ``NetworkPathStatus``, sampled when a
/// request fails.
///
/// A process-wide value rather than an argument threaded through every
/// repository: the network path is a device-wide fact, the repository stack is
/// assembled in several places, and none of them should have to know about it.
/// `NetworkMonitor` (in AppShared) pushes updates in; requests read it when they
/// fail.
///
/// The interface status and the debug force-offline override are stored
/// separately and combined on read. More than one monitor can exist (the app
/// shell builds a throwaway one, previews build their own), and every one of
/// them pushes the real path; were the override folded in before the push, a
/// second monitor's update would silently switch it off.
public enum NetworkPathProbe {
  private struct State {
    /// `nil` until a monitor delivers its first path.
    var interfaceSatisfied: Bool?
    var forcedOffline = false
  }

  private static let state = OSAllocatedUnfairLock(initialState: State())

  /// Record the interface status a path monitor just reported. Call it
  /// synchronously from the monitor's callback, so a request failing right
  /// after the path changes already sees the new status.
  public static func update(interfaceSatisfied: Bool) {
    state.withLock { $0.interfaceSatisfied = interfaceSatisfied }
  }

  /// Report `.unsatisfied` regardless of the interface while `forced` is set;
  /// clearing it restores the last reported interface status.
  public static func setForcedOffline(_ forced: Bool) {
    state.withLock { $0.forcedOffline = forced }
  }

  /// The path status right now, or `.unknown` if no monitor has reported one.
  public static func sample() -> NetworkPathStatus {
    state.withLock { state in
      if state.forcedOffline { return .unsatisfied }
      return switch state.interfaceSatisfied {
      case nil: .unknown
      case true?: .satisfied
      case false?: .unsatisfied
      }
    }
  }

  /// Back to "no monitor has reported", for tests.
  static func reset() {
    state.withLock { $0 = State() }
  }
}

/// What a connectivity-class transport failure most likely means.
///
/// Best effort, by design. A captive portal and a LAN-only server reached over
/// cellular both report a satisfied path and so read as
/// ``serverNotResponding``; VPN-required servers and IPv6-only paths can
/// mislead either way. Being right in the common cases still beats one
/// undifferentiated message for all of them.
public enum TransportFailureKind: Sendable, Equatable {
  /// The device has no network. The request never reached the server.
  case offline
  /// The device is online, but the server's hostname did not resolve.
  case hostNotFound
  /// The device is online and the hostname resolved (or was never looked up),
  /// but no server answered: connection refused, or the wait timed out.
  case serverNotResponding
  /// The device is online, but an established connection dropped before the
  /// server answered.
  case connectionLost

  /// Classify a transport failure, or `nil` if the code isn't
  /// connectivity-class (see ``RequestError/init(from:path:)`` for where the
  /// rest go).
  ///
  /// | path          | code                                          | kind                    |
  /// |---------------|-----------------------------------------------|-------------------------|
  /// | unsatisfied   | any connectivity code                         | `offline`               |
  /// | any           | `notConnectedToInternet`, `dataNotAllowed`, `internationalRoamingOff`, `callIsActive` | `offline` |
  /// | satisfied/unknown | `cannotFindHost`, `dnsLookupFailed`       | `hostNotFound`          |
  /// | satisfied/unknown | `cannotConnectToHost`, `timedOut`         | `serverNotResponding`   |
  /// | satisfied/unknown | `networkConnectionLost`                   | `connectionLost`        |
  ///
  /// The device-side codes win over a satisfied path: the path monitor lags
  /// the interface, and URLSession saying "not connected" is the more direct
  /// evidence. An unknown path falls back to the code alone.
  public init?(code: NSURLError, path: NetworkPathStatus) {
    let byCode: TransportFailureKind

    switch code {
    case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
      byCode = .offline
    case .cannotFindHost, .dnsLookupFailed:
      byCode = .hostNotFound
    case .cannotConnectToHost, .timedOut:
      byCode = .serverNotResponding
    case .networkConnectionLost:
      byCode = .connectionLost
    default:
      return nil
    }

    self = path == .unsatisfied ? .offline : byCode
  }
}
