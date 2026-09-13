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
    didSet { NetworkPathProbe.setForcedOffline(debugForceOffline) }
  }

  /// What the current path costs. One value, published as one value: the two
  /// facts are only meaningful together, and every consumer wants both.
  public private(set) var cost: LinkCost = .unrestricted

  @ObservationIgnored private let monitor = NWPathMonitor()
  @ObservationIgnored private let queue = DispatchQueue(label: "NetworkMonitor.queue")

  public init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let online = path.status == .satisfied
      // Synchronously, before the hop: `Networking` classifies a failed request
      // against the probe from whatever thread it failed on, and the observable
      // properties below only catch up after a hop to the main actor — too
      // late for a request failing right after the path changes.
      NetworkPathProbe.update(interfaceSatisfied: online)
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

  deinit {
    monitor.cancel()
  }
}
