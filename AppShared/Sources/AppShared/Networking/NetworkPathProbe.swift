//
//  NetworkPathProbe.swift
//  AppShared
//
//  One-shot network-path cost check for background runs. The long-lived
//  `NetworkMonitor` is part of the UI object graph and may not exist (or may
//  not have received a path update yet) when a background task fires in a
//  cold-launched process, so the coordinator probes the current path directly.
//

import Foundation
import Network

public enum NetworkPathProbe {
  /// The current path's raw cost — `isExpensive`/`isConstrained`, the same
  /// signal `NetworkMonitor` exposes. Callers combine this with a specific
  /// server's `syncOverCellular` opt-in via `SyncCondition`; this type makes
  /// no gating decision itself. Waits for the throwaway monitor's first path
  /// callback; an unknown path (timeout) reads as both expensive *and*
  /// constrained, so a heavy fill is conservatively skipped regardless of any
  /// server's opt-in rather than risked on an unread link.
  public static func currentCost(timeout: Duration = .seconds(2)) async -> (
    isExpensive: Bool, isConstrained: Bool
  ) {
    let monitor = NWPathMonitor()
    defer { monitor.cancel() }
    typealias Cost = (isExpensive: Bool, isConstrained: Bool)
    let verdicts = AsyncStream<Cost> { continuation in
      monitor.pathUpdateHandler = { path in
        continuation.yield((path.isExpensive, path.isConstrained))
        continuation.finish()
      }
    }
    monitor.start(queue: DispatchQueue(label: "NetworkPathProbe"))
    return await withTaskGroup(of: Cost.self) { group in
      group.addTask { await verdicts.first { _ in true } ?? (true, true) }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return (true, true)
      }
      let first = await group.next() ?? (true, true)
      group.cancelAll()
      return first
    }
  }
}
