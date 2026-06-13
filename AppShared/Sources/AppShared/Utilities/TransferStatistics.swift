//
//  TransferStatistics.swift
//  AppShared
//
//  App-level, persisted accumulation of the bytes the API moved, broken down by
//  `TransferCategory`. Fed from the `NetworkTransfer` sink (registered once via
//  `install()`); surfaced read-only in the Offline & Sync settings screen so the
//  Wi‑Fi gating can be tuned with evidence rather than guesswork.
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

  /// Register the `NetworkTransfer` sink. Each response hops onto the main actor
  /// to fold into the observable. Call once at app startup.
  public static func install() {
    NetworkTransfer.sink = { bytes, category in
      Task { @MainActor in shared.record(bytes: bytes, category: category) }
    }
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
