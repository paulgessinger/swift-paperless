//
//  UpdateThrottle.swift
//  AppShared
//
//  Caps how often fast-changing state reaches the screen.
//

import Foundation

/// Runs an update at most once per interval: the first at once, and while
/// the interval runs, only the latest one, when it ends. For `@Observable`
/// state that would otherwise repaint a screen on every change.
@MainActor
public final class UpdateThrottle {
  /// What the Offline & Sync screen can follow without the rows jittering.
  public static let displayInterval = Duration.milliseconds(500)

  private let interval: Duration
  private var lastRun: ContinuousClock.Instant?
  private var pending: (@MainActor () -> Void)?
  private var trailing: Task<Void, Never>?

  init(interval: Duration = UpdateThrottle.displayInterval) {
    self.interval = interval
  }

  func run(_ update: @escaping @MainActor () -> Void) {
    let now = ContinuousClock.now
    guard trailing == nil, let lastRun, now - lastRun < interval else {
      if trailing == nil {
        lastRun = now
        update()
      } else {
        pending = update
      }
      return
    }
    pending = update
    trailing = Task { [weak self, interval] in
      try? await Task.sleep(until: lastRun + interval)
      guard !Task.isCancelled else { return }
      self?.runPending()
    }
  }

  /// Drop the update waiting for the interval to end, if any.
  func cancel() {
    trailing?.cancel()
    trailing = nil
    pending = nil
  }

  private func runPending() {
    trailing = nil
    lastRun = .now
    let update = pending
    pending = nil
    update?()
  }
}
