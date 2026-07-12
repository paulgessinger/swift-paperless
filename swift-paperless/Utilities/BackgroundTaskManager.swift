//
//  BackgroundTaskManager.swift
//  swift-paperless
//
//  Stage 11 (background sync): the app shell's BGTaskScheduler wiring — the
//  only place in the project that imports BackgroundTasks (AppShared must stay
//  extension-safe). Registration happens in AppDelegate before launch
//  finishes; the handlers delegate to BackgroundSyncCoordinator, which decides
//  between the registered UI graph and a headless stack.
//
//  Requests are (re)submitted at launch, on scenePhase == .background, and at
//  the end of every background run — same-identifier submits replace the
//  pending request, so this is idempotent. The earliestBeginDate values are
//  floors, not cadences: the OS decides actual timing from its energy budget.
//

import AppShared
import BackgroundTasks
import Common
import Foundation
import os

@MainActor
enum BackgroundTaskManager {
  static let refreshIdentifier = "com.paulgessinger.swift-paperless.sync.refresh"
  static let processingIdentifier = "com.paulgessinger.swift-paperless.sync.processing"

  /// Register both handlers. Must run before `didFinishLaunching` returns.
  /// `using: .main` runs the launch handlers on the main queue, so
  /// `MainActor.assumeIsolated` is sound under strict concurrency.
  static func registerTasks() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: .main) {
      task in
      MainActor.assumeIsolated {
        handle(task, label: "refresh") { await BackgroundSyncCoordinator.shared.runRefresh() }
      }
    }
    BGTaskScheduler.shared.register(forTaskWithIdentifier: processingIdentifier, using: .main) {
      task in
      MainActor.assumeIsolated {
        handle(task, label: "processing") {
          await BackgroundSyncCoordinator.shared.runProcessing()
        }
      }
    }
  }

  /// Submit (or refresh) both pending requests.
  static func scheduleAll() {
    scheduleRefresh()
    scheduleProcessing()
  }

  // MARK: - Handling

  private static func handle(
    _ task: BGTask, label: String, _ body: @escaping @MainActor () async -> Bool
  ) {
    Logger.sync.info("Background task fired: \(label, privacy: .public)")
    let work = Task { @MainActor in
      await body()
    }
    // Expiration only cancels; cancellation propagates cooperatively into the
    // sync machinery, whose watermarks/checkpoints persist for the next run.
    task.expirationHandler = {
      Logger.sync.info("Background task expiring: \(label, privacy: .public); cancelling work")
      work.cancel()
    }
    Task { @MainActor in
      let success = await work.value
      scheduleAll()
      // The single completion site for this task, success and expiration alike.
      task.setTaskCompleted(success: success)
      Logger.sync.info(
        "Background task completed: \(label, privacy: .public) (success: \(success))")
    }
  }

  // MARK: - Scheduling

  private static func scheduleRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
    submit(request)
  }

  private static func scheduleProcessing() {
    // Skip — and drop any pending request — when no server wants the heavy
    // fill. Unknown (nil: no UI graph registered, e.g. scheduling from a
    // background launch) submits anyway; the handler no-ops cheaply rather
    // than opening a headless database just to decide.
    if BackgroundSyncCoordinator.shared.hasEntireLibraryServer() == false {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingIdentifier)
      return
    }
    let request = BGProcessingTaskRequest(identifier: processingIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = false
    submit(request)
  }

  private static func submit(_ request: BGTaskRequest) {
    do {
      try BGTaskScheduler.shared.submit(request)
      Logger.sync.debug("Submitted background task request \(request.identifier, privacy: .public)")
    } catch {
      // Expected on the simulator (.unavailable); never fatal.
      Logger.sync.info(
        "Background task submit failed for \(request.identifier, privacy: .public): \(describe(error), privacy: .public)"
      )
    }
  }

  /// `BGTaskSchedulerError` renders as an opaque `Code=N "(null)"`; spell out
  /// what each code actually means so the log line is actionable.
  private static func describe(_ error: any Error) -> String {
    guard let schedulerError = error as? BGTaskScheduler.Error else {
      return String(describing: error)
    }
    return switch schedulerError.code {
    case .unavailable:
      "unavailable — background tasks are unsupported here (simulator or app extension) "
        + "or Background App Refresh is off for this app (Settings, or Low Power Mode)"
    case .tooManyPendingTaskRequests:
      "too many pending task requests — submitted identifiers beyond the pending limit"
    case .notPermitted:
      "not permitted — identifier missing from BGTaskSchedulerPermittedIdentifiers "
        + "or the background mode capability is absent"
    case .immediateRunIneligible:
      "immediate run ineligible — the system declined to start this task right away"
    @unknown default:
      "unrecognized BGTaskSchedulerError code \(schedulerError.code.rawValue)"
    }
  }
}
