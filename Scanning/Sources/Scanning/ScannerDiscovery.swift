//
//  ScannerDiscovery.swift
//  Scanning
//

import Combine
import Foundation
import Observation
import SwiftESCL
import os

/// Browses the local network for eSCL scanners.
///
/// eSCL is advertised under two service types — `_uscans._tcp` for HTTPS and
/// `_uscan._tcp` for HTTP — and a scanner may appear under either or both, with
/// a *different* port and root path per transport. SwiftESCL's `ScannerBrowser`
/// handles one at a time, so this runs two and merges the results.
///
/// This is also the only file in the app that touches Combine. `ScannerBrowser`
/// is an `ObservableObject` and `@Observable` has no bridge to one, so the
/// subscription lives here and nothing outside the package sees it.
@MainActor
@Observable
public final class ScannerDiscovery {
  /// Everything found so far, merged across both transports and stably ordered.
  public private(set) var scanners: [ScannerRef] = []

  /// `true` once browsing has started and until it is stopped.
  public private(set) var isSearching = false

  @ObservationIgnored private var secureBrowser: ScannerBrowser?
  @ObservationIgnored private var plainBrowser: ScannerBrowser?
  @ObservationIgnored private var cancellables: Set<AnyCancellable> = []

  // Kept apart so a transport's disappearance can be reflected without losing
  // what the other one found.
  @ObservationIgnored private var secureFound: [ScannerRef] = []
  @ObservationIgnored private var plainFound: [ScannerRef] = []

  public init() {}

  /// Starts browsing, replacing any run already in progress.
  ///
  /// On iOS this is what triggers the Local Network permission prompt, so call
  /// it when the user has asked for a scanner and not before.
  public func start() {
    stop()

    Logger.scanning.info("Starting scanner discovery on both transports")

    let secure = ScannerBrowser(usePlainText: false)
    let plain = ScannerBrowser(usePlainText: true)

    subscribe(to: secure, usePlainText: false) { [weak self] in self?.secureFound = $0 }
    subscribe(to: plain, usePlainText: true) { [weak self] in self?.plainFound = $0 }

    secureBrowser = secure
    plainBrowser = plain
    isSearching = true

    secure.startDiscovery()
    plain.startDiscovery()
  }

  /// Stops browsing and forgets what was found.
  ///
  /// The browsers are dropped rather than reused: `stopDiscovery()` cancels the
  /// underlying `NWBrowser`, which cannot be restarted, and it leaves
  /// `discovered` populated — so a reused instance would resurrect scanners
  /// that are no longer there.
  public func stop() {
    guard isSearching || secureBrowser != nil || plainBrowser != nil else { return }

    secureBrowser?.stopDiscovery()
    plainBrowser?.stopDiscovery()
    secureBrowser = nil
    plainBrowser = nil
    cancellables.removeAll()

    secureFound = []
    plainFound = []
    scanners = []
    isSearching = false
  }

  private func subscribe(
    to browser: ScannerBrowser,
    usePlainText: Bool,
    store: @escaping @MainActor ([ScannerRef]) -> Void
  ) {
    browser.$discovered
      .sink { [weak self] discovered in
        // `@Published` fires in `willSet`, so this closure's argument is the new
        // value while `browser.discovered` is still the old one — always use the
        // argument. `discovered` is main-actor state and every path that writes
        // it in `ScannerBrowser` hops to main first, so the assumption holds.
        MainActor.assumeIsolated {
          guard let self else { return }
          // Map here, not later: holding on to `[EsclScanner]` would put those
          // non-`Sendable` instances in the main-actor region, which is exactly
          // what stops them being usable from `ScannerClient`.
          store(discovered.map { ScannerRef($0, usePlainText: usePlainText) })
          self.merge()
        }
      }
      .store(in: &cancellables)
  }

  private func merge() {
    scanners = Self.merge(secure: secureFound, plain: plainFound)
  }

  /// Merges the two transports' findings.
  ///
  /// Both derive their `id` from the TXT record's `uuid`, so it joins exactly.
  /// Records are replaced whole and never field-merged: the transports
  /// advertise different ports *and* different root paths, so a mixture of the
  /// two would address a scanner that is not there. HTTPS wins, because a
  /// scanner offering it expects to be talked to that way.
  static func merge(secure: [ScannerRef], plain: [ScannerRef]) -> [ScannerRef] {
    var byID: [String: ScannerRef] = [:]
    for ref in plain { byID[ref.id] = ref }
    for ref in secure { byID[ref.id] = ref }

    // Dictionary order is not stable across runs, and an unstable list makes
    // SwiftUI reshuffle rows under the user's finger.
    return byID.values.sorted { lhs, rhs in
      switch lhs.displayName.localizedStandardCompare(rhs.displayName) {
      case .orderedAscending: true
      case .orderedDescending: false
      // Two scanners with the same name still need a deterministic order.
      case .orderedSame: lhs.id < rhs.id
      }
    }
  }
}
