//
//  ErrorSuppression.swift
//  AppShared
//
//  The app's policy for which errors never become a user-visible banner,
//  because a dedicated UI surface already represents the condition.
//
//  This policy governs *incidental* failures only — the background sweeps and
//  on-appear loads nobody asked for. Failures the user asked for go through
//  the entry points in `UserInitiatedErrors.swift`, which consult it either
//  partially (reads) or not at all (mutations).
//

import Foundation
import Networking

extension ErrorController {
  /// Teach the controller about the link: which errors the connection-status
  /// surfaces already cover, and how to tell "this device is offline" from
  /// "this server didn't answer".
  ///
  /// Suppressed are every 401 (the banner offers re-auth) and connectivity-
  /// class errors while the device is offline (the offline toast says so). A
  /// server that is unreachable while the device *is* online still surfaces —
  /// that's a real per-server problem the banners say nothing about.
  ///
  /// "While offline" is the monitor's verdict when the error is *pushed*: the
  /// question is whether the offline surface is showing now. Which errors count
  /// as connectivity-class uses the error's own failure-time classification
  /// where it has one (see `connectivityFailure`).
  @MainActor
  public func installConnectivityPolicy(networkMonitor: NetworkMonitor) {
    shouldSuppress = { [weak networkMonitor] error in
      Self.isBannerCovered(error, offline: networkMonitor?.isOnline == false)
    }
    isOffline = { [weak networkMonitor] in
      networkMonitor?.isOnline == false
    }
  }

  static func isBannerCovered(_ error: any Error, offline: Bool) -> Bool {
    if let request = error as? RequestError, case .unauthorized = request {
      return true
    }

    guard offline else { return false }

    return isConnectivityError(error)
  }

  /// How much a connectivity-class transport failure tells us about whether
  /// the request reached the server. The distinction only matters for writes:
  /// for a read, either way nothing was lost.
  enum ConnectivityFailure {
    /// The request never left the device, so the server did not see it.
    case neverSent
    /// The link died or the wait expired mid-flight. The server may well have
    /// processed the request before the connection went away — a retry can
    /// duplicate a note, a tag or a share link.
    case unconfirmed
  }

  /// Classify a transport failure, or `nil` if it isn't connectivity-class.
  ///
  /// The code list is the same for every error shape; `isConnectivityError`
  /// is just "did this classify at all", so the two can't drift apart.
  ///
  /// A repository's failures arrive as `RequestError.connectivity`, which also
  /// carries the device-offline verdict taken when the request failed. That
  /// adds one thing over the code alone: a host lookup or connect that failed
  /// (`cannotFindHost`, `cannotConnectToHost`, ...) *because the path was down*
  /// never reached a server, so it counts too. The same codes on a working path
  /// still don't — that's the server being unreachable, which must surface.
  /// Raw `URLError`s (paths that don't go through a repository, e.g. image
  /// loading) carry no verdict and keep the code-only rule.
  static func connectivityFailure(_ error: any Error) -> ConnectivityFailure? {
    func classify(_ code: Int) -> ConnectivityFailure? {
      switch code {
      case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed:
        .neverSent
      case NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut:
        .unconfirmed
      default:
        nil
      }
    }

    if let request = error as? RequestError, case .connectivity(let code, let kind, _) = request {
      if let failure = classify(code.rawValue) {
        return failure
      }
      return kind == .offline ? .neverSent : nil
    }

    if let url = error as? URLError, let failure = classify(url.code.rawValue) {
      return failure
    }

    if let ns = error as NSError?, ns.domain == NSURLErrorDomain {
      return classify(ns.code)
    }

    return nil
  }

  /// Transport failures that mean "the request did not complete over the
  /// network" — the union of both `ConnectivityFailure` cases.
  static func isConnectivityError(_ error: any Error) -> Bool {
    connectivityFailure(error) != nil
  }
}
