//
//  BackgroundTaskManager.swift
//  swift-paperless
//
//  The app's BGTaskScheduler wiring. What a task does is
//  `AppShared.BackgroundSync`; this file registers, schedules and completes.
//
//  Requests are submitted at launch, on entering the background, and after
//  every run. A submit replaces the pending request with the same identifier,
//  so this is idempotent. The earliestBeginDate values are floors: iOS picks
//  the actual time from its energy budget and the app's usage.
//

import AppShared
import BackgroundTasks
import Foundation
import os

@MainActor
enum BackgroundTaskManager {
  /// Cheap phases for every server. This is the task that runs when the app
  /// isn't opened for days.
  static let refreshIdentifier = "com.paulgessinger.swift-paperless.sync.refresh"
  /// Every phase, including the *Entire library* fill. Mostly runs overnight.
  static let processingIdentifier = "com.paulgessinger.swift-paperless.sync.processing"

  /// Registers both handlers. Must run before `didFinishLaunching` returns.
  static func registerTasks() {
    // `using: .main` runs the launch handlers on the main queue.
    BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: .main) {
      task in
      MainActor.assumeIsolated { handle(task, label: "refresh", allowsFill: false) }
    }
    BGTaskScheduler.shared.register(forTaskWithIdentifier: processingIdentifier, using: .main) {
      task in
      MainActor.assumeIsolated { handle(task, label: "processing", allowsFill: true) }
    }
  }

  static func scheduleAll() {
    scheduleRefresh()
    scheduleProcessing()
  }

  // MARK: - Handling

  private static func handle(_ task: BGTask, label: String, allowsFill: Bool) {
    Logger.sync.info("Background task started: \(label, privacy: .public)")
    let stack: AppStack
    do {
      stack = try AppStackHolder.shared()
    } catch {
      // Before first unlock, for example. Never wipe or fall back to an
      // in-memory database here; the next run tries again.
      Logger.sync.error(
        "Background task \(label, privacy: .public) could not open the database: \(error)")
      scheduleAll()
      task.setTaskCompleted(success: false)
      return
    }

    let work = Task { @MainActor in
      await BackgroundSync.run(stack: stack, allowsFill: allowsFill)
    }
    task.expirationHandler = {
      Task { @MainActor in
        Logger.sync.info("Background task expiring: \(label, privacy: .public)")
        // Stops the sessions' steps and suspends the writer, then ends the sweep.
        AppStackHolder.suspension.expire()
        work.cancel()
      }
    }
    Task { @MainActor in
      let completed = await work.value
      scheduleAll()
      // The one completion site, for success and expiry alike.
      task.setTaskCompleted(success: completed)
      Logger.sync.info(
        "Background task finished: \(label, privacy: .public) (completed: \(completed))")
    }
  }

  // MARK: - Scheduling

  private static func scheduleRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
    submit(request)
  }

  private static func scheduleProcessing() {
    // Without a stack, submit anyway: the run itself finds out.
    if let stack = try? AppStackHolder.shared(), !BackgroundSync.hasEntireLibraryServer(in: stack) {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingIdentifier)
      return
    }
    let request = BGProcessingTaskRequest(identifier: processingIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)
    request.requiresNetworkConnectivity = true
    submit(request)
  }

  private static func submit(_ request: BGTaskRequest) {
    do {
      try BGTaskScheduler.shared.submit(request)
      Logger.sync.debug("Submitted background task \(request.identifier, privacy: .public)")
    } catch {
      // Expected on the simulator; never fatal.
      Logger.sync.info(
        "Submitting background task \(request.identifier, privacy: .public) failed: \(describe(error), privacy: .public)"
      )
    }
  }

  /// `BGTaskScheduler.Error` logs as an opaque code; say what each one means.
  private static func describe(_ error: any Error) -> String {
    guard let schedulerError = error as? BGTaskScheduler.Error else {
      return String(describing: error)
    }
    return switch schedulerError.code {
    case .unavailable:
      "unavailable: unsupported here (simulator) or Background App Refresh is off "
        + "(Settings, or Low Power Mode)"
    case .tooManyPendingTaskRequests:
      "too many pending task requests"
    case .notPermitted:
      "not permitted: identifier missing from BGTaskSchedulerPermittedIdentifiers "
        + "or background mode missing"
    case .immediateRunIneligible:
      "immediate run ineligible"
    @unknown default:
      "unknown BGTaskScheduler error \(schedulerError.code.rawValue)"
    }
  }
}
