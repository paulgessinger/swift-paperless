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

import Foundation
import Network
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
  public var debugForceOffline: Bool = false

  public private(set) var isExpensive: Bool = false
  public private(set) var isConstrained: Bool = false

  @ObservationIgnored private let monitor = NWPathMonitor()
  @ObservationIgnored private let queue = DispatchQueue(label: "NetworkMonitor.queue")

  public init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let online = path.status == .satisfied
      let expensive = path.isExpensive
      let constrained = path.isConstrained
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.interfaceOnline != online {
          Logger.shared.info(
            "NetworkMonitor: interfaceOnline \(self.interfaceOnline) -> \(online)")
          self.interfaceOnline = online
        }
        if self.isExpensive != expensive { self.isExpensive = expensive }
        if self.isConstrained != constrained { self.isConstrained = constrained }
      }
    }
    monitor.start(queue: queue)
  }

  deinit {
    monitor.cancel()
  }
}

extension NetworkMonitor {
  /// Whether the *proactive* sweeps (library fill, detail fill) may run right
  /// now. Interactive work the user asked for is never gated on this.
  ///
  /// Low Data Mode (`isConstrained`) always wins: it is an explicit instruction
  /// from the user to the whole system, not a guess about the link, so a
  /// per-server "sync over cellular" opt-in does not override it. `isExpensive`
  /// — cellular, or a personal hotspot — is what the opt-in is for.
  public func allowsProactiveSync(syncOverCellular: Bool) -> Bool {
    if isConstrained { return false }
    return syncOverCellular || !isExpensive
  }
}
