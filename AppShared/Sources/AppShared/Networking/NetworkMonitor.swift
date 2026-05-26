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
  public private(set) var isOnline: Bool = true
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
        if self.isOnline != online {
          Logger.shared.info("NetworkMonitor: isOnline \(self.isOnline) -> \(online)")
          self.isOnline = online
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
