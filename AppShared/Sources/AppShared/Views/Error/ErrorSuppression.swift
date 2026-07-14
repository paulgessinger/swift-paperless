//
//  ErrorSuppression.swift
//  AppShared
//
//  The app's policy for which errors never become a user-visible banner,
//  because a dedicated UI surface already represents the condition.
//

import Foundation
import Networking

extension ErrorController {
  /// Suppress the errors the connection-status surfaces already cover: every
  /// 401 (the banner offers re-auth), and connectivity-class errors while the
  /// device is offline (the offline toast says so). A server that is
  /// unreachable while the device *is* online still surfaces — that's a real
  /// per-server problem the banners say nothing about.
  @MainActor
  public func suppressBannerCoveredErrors(networkMonitor: NetworkMonitor) {
    shouldSuppress = { [weak networkMonitor] error in
      Self.isBannerCovered(error, offline: networkMonitor?.isOnline == false)
    }
  }

  static func isBannerCovered(_ error: any Error, offline: Bool) -> Bool {
    if let request = error as? RequestError, case .unauthorized = request {
      return true
    }

    guard offline else { return false }

    // Repositories normalize transport failures into `RequestError`, so this is
    // the case an offline API call actually arrives as. The raw `URLError` /
    // `NSError` checks below still matter for the paths that don't go through a
    // repository (image loading, for one).
    if let request = error as? RequestError, case .connectivity(let code, _) = request {
      switch code {
      case .notConnectedToInternet, .networkConnectionLost,
        .dataNotAllowed, .timedOut:
        return true
      default: break
      }
    }

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
