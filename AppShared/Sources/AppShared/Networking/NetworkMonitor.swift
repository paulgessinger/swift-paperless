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

  /// Counts changes of the route to the network while a path is in use, such as
  /// a VPN tunnel coming up, which `isOnline` doesn't show: the device was
  /// already online. Observe it to retry what failed on the previous route.
  public private(set) var routeChangeCount = 0

  /// Whether a path has been reported. Until then `isOnline` and `cost` are
  /// defaults, not readings.
  @ObservationIgnored private var hasReportedPath = false

  @ObservationIgnored private var route: [String]?
  @ObservationIgnored private var backgroundedAt: ContinuousClock.Instant?

  /// How long the app stays in the background before its pooled connections are
  /// presumed dead.
  private static let staleConnectionAge: Duration = .seconds(30)

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
      let route = path.availableInterfaces.map(\.name) + path.gateways.map(\.debugDescription)
      ConnectionEpoch.shared.update(route: route)
      let cost = LinkCost(isExpensive: path.isExpensive, isConstrained: path.isConstrained)
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.interfaceOnline != online {
          Logger.shared.info(
            "NetworkMonitor: interfaceOnline \(self.interfaceOnline) -> \(online)")
          self.interfaceOnline = online
        }
        if self.cost != cost { self.cost = cost }
        if let previous = self.route, previous != route {
          Logger.shared.info("NetworkMonitor: route changed")
          self.routeChangeCount += 1
        }
        self.route = route
        self.hasReportedPath = true
      }
    }
    monitor.start(queue: queue)
  }

  deinit {
    monitor.cancel()
  }

  /// Call when the app moves to the background.
  public func didEnterBackground() {
    backgroundedAt = .now
  }

  /// Call when the app returns to the foreground, before its first request.
  public func willEnterForeground() {
    defer { backgroundedAt = nil }
    guard let backgroundedAt, backgroundedAt.duration(to: .now) >= Self.staleConnectionAge
    else { return }
    ConnectionEpoch.shared.invalidate()
  }

  /// The current path's cost, or `nil` if there is no usable path.
  ///
  /// For a process iOS just launched, which has had no path callback yet: waits
  /// for the first one. After `timeout` it reads `.unknown` (expensive and
  /// constrained), so a fill is skipped rather than risked.
  public func currentCost(timeout: Duration = .seconds(2)) async -> LinkCost? {
    let deadline = ContinuousClock.now + timeout
    while !hasReportedPath {
      guard ContinuousClock.now < deadline else { return .unknown }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return isOnline ? cost : nil
  }
}
