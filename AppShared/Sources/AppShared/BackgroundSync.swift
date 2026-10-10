//
//  BackgroundSync.swift
//  AppShared
//
//  What a background task does, without UIKit or BackgroundTasks: the app
//  target schedules the tasks and calls in here.
//

import DataModel
import Foundation
import os

@MainActor
public enum BackgroundSync {
  /// Sync every server once, stalest first.
  ///
  /// The whole sweep is one piece of background work, so the database writer
  /// stays open between servers. Cancelling the calling task stops it before
  /// the next server. The task as a whole gets a `sync_run` row of its own
  /// (step `task`, no server), and the per-server runs carry its trigger.
  ///
  /// - Parameter trigger: `.refreshTask` limits every server to the cheap
  ///   phases; `.processingTask` allows the fill.
  /// - Returns: `false` if the sweep was cancelled.
  public static func run(stack: AppStack, trigger: SyncTrigger) async -> Bool {
    TransferStatistics.install()
    let context = SyncRunContext(trigger: trigger)
    let recorder = SyncRunRecorder(database: stack.database, serverID: nil)
    let completed = await SyncRunContext.$current.withValue(context) {
      await stack.suspension.performBackgroundWork {
        let row = await recorder.begin(.task)
        guard let cost = await stack.networkMonitor.currentCost() else {
          Logger.sync.info("Background sync skipped: no network")
          await recorder.end(row, .skipped, message: "no network")
          return true
        }
        let completed = await stack.syncEngine.syncAllServers(
          allowsFill: trigger == .processingTask, cost: cost)
        // After expiry the writer is already suspended, so this write is lost
        // and the row is closed as interrupted at the next launch.
        await recorder.end(row, completed ? .ok : .cancelled)
        return completed
      }
    }
    TransferStatistics.shared.persist()
    return completed
  }

  /// Whether any server downloads its entire library, which is what the
  /// long background task is for.
  public static func hasEntireLibraryServer(in stack: AppStack) -> Bool {
    stack.connectionManager.connections.values.contains {
      $0.offlineBrowsingMode == .entireLibrary
    }
  }
}
