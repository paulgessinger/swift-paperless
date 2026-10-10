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
  /// the next server.
  ///
  /// - Parameter allowsFill: `false` limits every server to the cheap phases.
  /// - Returns: `false` if the sweep was cancelled.
  public static func run(stack: AppStack, allowsFill: Bool) async -> Bool {
    TransferStatistics.install()
    guard let cost = await stack.networkMonitor.currentCost() else {
      Logger.sync.info("Background sync skipped: no network")
      return true
    }
    let completed = await stack.suspension.performBackgroundWork {
      await stack.syncEngine.syncAllServers(allowsFill: allowsFill, cost: cost)
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
