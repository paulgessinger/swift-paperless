//
//  BackgroundTaskManager.swift
//  swift-paperless
//
//  The app's BGTaskScheduler wiring. What a task does is
//  `AppShared.BackgroundSync`; this file registers, schedules and completes.
//
//  A submit replaces the pending request with the same identifier, and with
//  it that request's earliest begin date. So a task is resubmitted only once
//  it has run, and the launch and background-entry checks submit only what
//  is not pending. The earliestBeginDate values are floors: iOS picks the
//  actual time from its energy budget and the app's usage.
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
      MainActor.assumeIsolated { handle(task, label: "refresh", trigger: .refreshTask) }
    }
    BGTaskScheduler.shared.register(forTaskWithIdentifier: processingIdentifier, using: .main) {
      task in
      MainActor.assumeIsolated { handle(task, label: "processing", trigger: .processingTask) }
    }
  }

  /// Submits the requests that are not pending, and withdraws the processing
  /// request when no server needs it any more. Pending requests keep their
  /// dates.
  static func ensureScheduled() {
    BGTaskScheduler.shared.getPendingTaskRequests { pending in
      let identifiers = Set(pending.map(\.identifier))
      Task { @MainActor in
        if !identifiers.contains(refreshIdentifier) {
          scheduleRefresh()
        }
        if !wantsProcessing() {
          BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingIdentifier)
        } else if !identifiers.contains(processingIdentifier) {
          scheduleProcessing()
        }
      }
    }
  }

  // MARK: - Handling

  private static func handle(_ task: BGTask, label: String, trigger: SyncTrigger) {
    Logger.sync.info("Background task started: \(label, privacy: .public)")
    let work = Task { @MainActor in
      do {
        let stack = try AppStackHolder.shared()
        return await BackgroundSync.run(stack: stack, trigger: trigger)
      } catch {
        // Before first unlock, for example. Never wipe or fall back to an
        // in-memory database here; the next run tries again.
        Logger.sync.error(
          "Background task \(label, privacy: .public) could not open the database: \(error)")
        return false
      }
    }
    // iOS calls this shortly before the task's time is up; the task has to
    // complete promptly afterwards or the app is terminated.
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
      // Only this task's own request: the other one keeps its date.
      reschedule(task.identifier)
      // The one completion site, for success, failure and expiry alike.
      task.setTaskCompleted(success: completed)
      Logger.sync.info(
        "Background task finished: \(label, privacy: .public) (completed: \(completed))")
    }
  }

  // MARK: - Scheduling

  private static func reschedule(_ identifier: String) {
    switch identifier {
    case refreshIdentifier: scheduleRefresh()
    case processingIdentifier where wantsProcessing(): scheduleProcessing()
    default: break
    }
  }

  /// Without a stack, yes: the run itself finds out.
  private static func wantsProcessing() -> Bool {
    guard let stack = try? AppStackHolder.shared() else { return true }
    return BackgroundSync.hasEntireLibraryServer(in: stack)
  }

  private static func scheduleRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
    submit(request)
  }

  private static func scheduleProcessing() {
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
