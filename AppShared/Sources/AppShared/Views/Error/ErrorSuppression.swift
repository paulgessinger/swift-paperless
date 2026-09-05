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

  /// Transport failures that mean "the request never reached the server".
  /// Note this cannot distinguish device-offline from server-unreachable on
  /// its own (see #667) — callers pair it with the NetworkMonitor's verdict.
  static func isConnectivityError(_ error: any Error) -> Bool {
    if let url = error as? URLError {
      switch url.code {
      case .notConnectedToInternet, .networkConnectionLost,
        .dataNotAllowed, .timedOut:
        return true
      default: break
      }
    }

    if let ns = error as NSError?, ns.domain == NSURLErrorDomain {
      switch ns.code {
      case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
        NSURLErrorDataNotAllowed, NSURLErrorTimedOut:
        return true
      default: break
      }
    }

    return false
  }
}
