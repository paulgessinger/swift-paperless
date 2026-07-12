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
  /// Whether the current network path is unmetered — the same semantics the
  /// foreground gate uses (`!isExpensive && !isConstrained`). Waits for the
  /// throwaway monitor's first path callback; an unknown path (timeout) reads
  /// as **metered**, so heavy fills are conservatively skipped rather than
  /// risked on cellular.
  public static func isUnmetered(timeout: Duration = .seconds(2)) async -> Bool {
    let monitor = NWPathMonitor()
    defer { monitor.cancel() }
    let verdicts = AsyncStream<Bool> { continuation in
      monitor.pathUpdateHandler = { path in
        continuation.yield(!path.isExpensive && !path.isConstrained)
        continuation.finish()
      }
    }
    monitor.start(queue: DispatchQueue(label: "NetworkPathProbe"))
    return await withTaskGroup(of: Bool.self) { group in
      group.addTask { await verdicts.first { _ in true } ?? false }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }
  }
}
