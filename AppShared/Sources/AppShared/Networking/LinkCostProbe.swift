//
//  LinkCostProbe.swift
//  AppShared
//

import DataModel
import Foundation
import Network

/// A one-shot read of the current network path, for a process iOS just
/// launched in the background. ``NetworkMonitor`` reads `.unrestricted` until
/// its first path callback, so it can't be trusted that early.
public enum LinkCostProbe {
  /// The current path's cost, or `nil` if there is no usable path.
  ///
  /// A path that hasn't been reported within `timeout` reads as `.unknown`
  /// (expensive and constrained), so the fill is skipped rather than risked.
  public static func current(timeout: Duration = .seconds(2)) async -> LinkCost? {
    let monitor = NWPathMonitor()
    defer { monitor.cancel() }
    let paths = AsyncStream<LinkCost?> { continuation in
      monitor.pathUpdateHandler = { path in
        continuation.yield(
          path.status == .satisfied
            ? LinkCost(isExpensive: path.isExpensive, isConstrained: path.isConstrained)
            : nil)
        continuation.finish()
      }
    }
    monitor.start(queue: DispatchQueue(label: "LinkCostProbe"))
    return await withTaskGroup(of: LinkCost??.self) { group in
      group.addTask {
        for await cost in paths { return .some(cost) }
        return .some(.unknown)
      }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return .some(.unknown)
      }
      let first = await group.next() ?? .some(.unknown)
      group.cancelAll()
      return first ?? .unknown
    }
  }
}
