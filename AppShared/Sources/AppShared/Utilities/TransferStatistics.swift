//
//  TransferStatistics.swift
//  AppShared
//
//  App-level, persisted accumulation of the bytes the API moved, broken down by
//  `TransferCategory`. Fed from the `NetworkTransfer` sink (registered once via
//  `install()`); surfaced read-only in the Offline & Sync settings screen so the
//  Wi‑Fi gating can be tuned with evidence rather than guesswork.
//
//  Counts *wire* bytes for API requests — headers and body, both directions,
//  as reported by the task metrics. File downloads and thumbnails take other
//  paths and are deliberately excluded: they are explicit, user-driven
//  transfers rather than background fills.
//

import Common
import Foundation
import Networking
import os

@MainActor
@Observable
public final class TransferStatistics {
  public static let shared = TransferStatistics()

  /// Cumulative bytes received per category since ``since``.
  public private(set) var bytesByCategory: [TransferCategory: Int64] = [:]
  /// When counting started (set on first use and on `reset()`).
  public private(set) var since: Date = .init()

  public var total: Int64 { bytesByCategory.values.reduce(0, +) }

  private static let storeKey = "transferStatistics.v1"
  private var defaults: UserDefaults { UserDefaults(suiteName: ContentStore.appGroup) ?? .standard }

  private init() { load() }

  /// Coalescing buffer between the response threads and the main actor.
  ///
  /// A hop per response was one unstructured `Task` and one `@Observable`
  /// mutation for every single request — and an uncapped detail fill issues one
  /// request per document, so a large library produced thousands of main-actor
  /// hops and SwiftUI invalidations for a number that changes by a few kilobytes
  /// each time. Responses now accumulate under a lock and drain at most once per
  /// ``drainInterval``.
  private final class Coalescer: @unchecked Sendable {
    static let shared = Coalescer()
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private struct State {
      var pending: [TransferCategory: Int] = [:]
      var draining = false
    }

    static let drainInterval = Duration.seconds(1)

    func add(bytes: Int, category: TransferCategory) {
      let shouldSchedule = lock.withLock { state -> Bool in
        state.pending[category, default: 0] += bytes
        guard !state.draining else { return false }
        state.draining = true
        return true
      }
      guard shouldSchedule else { return }
      Task { @MainActor in
        try? await Task.sleep(for: Self.drainInterval)
        self.drain()
      }
    }

    @MainActor
    func drain() {
      let pending = lock.withLock { state -> [TransferCategory: Int] in
        defer {
          state.pending = [:]
          state.draining = false
        }
        return state.pending
      }
      for (category, bytes) in pending {
        TransferStatistics.shared.record(bytes: bytes, category: category)
      }
    }
  }

  /// Register the `NetworkTransfer` sink. Idempotent: a `View` initializer is not
  /// a once-per-launch guarantee (a parent re-render, or a database-bootstrap
  /// retry, runs it again), and `NetworkTransfer.sink` is documented as being
  /// assigned once before any request runs.
  private static var installed = false
  public static func install() {
    guard !installed else { return }
    installed = true
    NetworkTransfer.sink = { bytes, category in
      Coalescer.shared.add(bytes: bytes, category: category)
    }
  }

  /// Flush anything the coalescer is still holding — called before persisting,
  /// so a background transition doesn't drop the last second of traffic.
  public static func flush() {
    Coalescer.shared.drain()
  }

  public func record(bytes: Int, category: TransferCategory) {
    bytesByCategory[category, default: 0] += Int64(bytes)
  }

  public func reset() {
    bytesByCategory = [:]
    since = .init()
    persist()
  }

  // Persist on demand (the app flushes on background); a stats meter losing the
  // tail of one session on a crash is acceptable.
  private struct Stored: Codable {
    var bytes: [String: Int64]
    var since: Date
  }

  public func persist() {
    Self.flush()
    let stored = Stored(
      bytes: Dictionary(uniqueKeysWithValues: bytesByCategory.map { ($0.key.rawValue, $0.value) }),
      since: since)
    do {
      defaults.set(try JSONEncoder().encode(stored), forKey: Self.storeKey)
    } catch {
      Logger.shared.error("TransferStatistics persist failed: \(error)")
    }
  }

  private func load() {
    guard let data = defaults.data(forKey: Self.storeKey),
      let stored = try? JSONDecoder().decode(Stored.self, from: data)
    else { return }
    bytesByCategory = Dictionary(
      uniqueKeysWithValues: stored.bytes.compactMap { key, value in
        TransferCategory(rawValue: key).map { ($0, value) }
      })
    since = stored.since
  }
}
