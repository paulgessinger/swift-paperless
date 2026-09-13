//
//  NetworkMonitor.swift
//  AppShared
//
//  Observable global wrapper around NWPathMonitor. Drives the offline branch
//  of `ConnectionStatusBanner` and gates the connectivity-error suppression
//  in `ErrorController`. The decorator does not consult this; views do.
//
//  Reports *interface* status, not server reachability. Captive portals,
//  VPN-required local servers, and IPv6-only paths can produce false
//  positives — used here as the source of the "device offline" signal only.
//

import DataModel
import Foundation
import Network
import Networking
import os

@MainActor
@Observable
public final class NetworkMonitor {
  // Effective online state, considering the debug override.
  public var isOnline: Bool {
    interfaceOnline && !debugForceOffline
  }

  // Raw NWPathMonitor signal. Exposed mainly for debugging surfaces that
  // want to display "actually online but forced offline."
  public private(set) var interfaceOnline: Bool = true

  // When true, `isOnline` reports false regardless of the real interface
  // status. Toggled from the in-app debug menu to exercise the offline UI
  // without disrupting the device's actual network.
  public var debugForceOffline: Bool = false {
    didSet { pathSnapshot.setForcedOffline(debugForceOffline) }
  }

  /// What the current path costs. One value, published as one value: the two
  /// facts are only meaningful together, and every consumer wants both.
  public private(set) var cost: LinkCost = .unrestricted

  @ObservationIgnored private let monitor = NWPathMonitor()
  @ObservationIgnored private let queue = DispatchQueue(label: "NetworkMonitor.queue")

  // Lock-protected mirror of `isOnline`, readable from any thread. A request
  // fails wherever it fails, and the observable properties above only catch up
  // after a hop to the main actor — too late, and too isolated, to classify
  // the failure against.
  @ObservationIgnored private let pathSnapshot = PathSnapshot()

  public init() {
    monitor.pathUpdateHandler = { [weak self, pathSnapshot] path in
      let online = path.status == .satisfied
      // Synchronously, before the hop: a request failing right after the path
      // changes must already see the new status.
      pathSnapshot.setInterfaceSatisfied(online)
      let cost = LinkCost(isExpensive: path.isExpensive, isConstrained: path.isConstrained)
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.interfaceOnline != online {
          Logger.shared.info(
            "NetworkMonitor: interfaceOnline \(self.interfaceOnline) -> \(online)")
          self.interfaceOnline = online
        }
        if self.cost != cost { self.cost = cost }
      }
    }
    monitor.start(queue: queue)
  }

  /// Make this monitor the path status `Networking` samples when a request
  /// fails, so the failure is classified as device-offline or
  /// server-unreachable against the network as it was at that moment. Install
  /// one monitor, once, at launch; a later install replaces it.
  public func installAsNetworkPathProbe() {
    NetworkPathProbe.install { [pathSnapshot] in pathSnapshot.status }
  }

  deinit {
    monitor.cancel()
  }
}

private final class PathSnapshot: Sendable {
  private struct State {
    // `nil` until NWPathMonitor delivers its first path.
    var interfaceSatisfied: Bool?
    var forcedOffline = false
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  func setInterfaceSatisfied(_ satisfied: Bool) {
    state.withLock { $0.interfaceSatisfied = satisfied }
  }

  func setForcedOffline(_ forced: Bool) {
    state.withLock { $0.forcedOffline = forced }
  }

  var status: NetworkPathStatus {
    state.withLock { state in
      if state.forcedOffline { return .unsatisfied }
      return switch state.interfaceSatisfied {
      case nil: .unknown
      case true?: .satisfied
      case false?: .unsatisfied
      }
    }
  }
}
