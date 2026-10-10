//
//  SyncRunContext.swift
//  AppShared
//
//  The persistent sync step record. Each step writes a `sync_run` row when it
//  starts and closes it when it ends; the steps of one pass share a run id,
//  carried by a task-local so a step needs nothing from its caller. `TaskSlot`
//  starts plain `Task {}`s, which inherit it, so joiners share the starter's
//  run and a step records once.
//

import Foundation
import Persistence
import os

/// What started a sync run. Stored by raw value.
public enum SyncTrigger: String, Sendable {
  /// An on-appear or launch sync of the active server.
  case foreground
  /// Pull-to-refresh or "Sync now".
  case userInitiated
  /// The engine's inactive-server sweep.
  case sweep
  /// The throttle-exempt first sync of a server that just appeared.
  case newServer
  /// A cache heal after a lost write.
  case heal
  /// The short background task (cheap phases).
  case refreshTask
  /// The long background task (every phase).
  case processingTask
}

/// One recorded step. Stored by raw value.
public enum SyncStep: String, Sendable {
  case connection, elements, reconcile, libraryFill, detailFill
  /// A background task as a whole (`server_id` NULL).
  case task
}

/// How a step ended. Stored by raw value; `interrupted` is written by
/// `closeInterruptedSyncSteps` for rows the previous process left open.
public enum SyncOutcome: String, Sendable {
  case ok, partial, failed, cancelled, skipped
}

public struct SyncRunContext: Sendable {
  public let id: UUID
  public let trigger: SyncTrigger

  public init(trigger: SyncTrigger) {
    id = UUID()
    self.trigger = trigger
  }

  /// The run the current task is part of, if any.
  @TaskLocal public static var current: SyncRunContext?

  /// A new run under the current trigger, or `fallback` when there is none:
  /// a background sweep's per-server runs keep the task's trigger.
  public static func child(_ fallback: SyncTrigger) -> SyncRunContext {
    SyncRunContext(trigger: current?.trigger ?? fallback)
  }
}

/// Writes a step's rows. Every write runs in its own unstructured task,
/// which is not cancelled with the step: the end of a cancelled step is
/// exactly what the record is for, and GRDB's async access would otherwise
/// abort it. Awaiting the task keeps the step inside its background work, so
/// the writer is still open. A failed write (the server row is gone, or the
/// writer was suspended by expiry) costs only the row.
struct SyncRunRecorder: Sendable {
  let database: Database
  /// `nil` for background-task rows.
  let serverID: UUID?

  /// Opens the row; `nil` when the write failed.
  func begin(_ step: SyncStep, at date: Date = Date()) async -> Int64? {
    let context = SyncRunContext.current ?? SyncRunContext(trigger: .foreground)
    return await Task {
      do {
        return try await database.beginSyncStep(
          runID: context.id, serverID: serverID, trigger: context.trigger.rawValue,
          step: step.rawValue, at: date)
      } catch {
        Logger.sync.debug(
          "Sync run row for \(step.rawValue, privacy: .public) not written: \(error)")
        return nil
      }
    }.value
  }

  func end(
    _ id: Int64?, _ outcome: SyncOutcome, message: String? = nil, succeeded: Int? = nil,
    failed: Int? = nil, at date: Date = Date()
  ) async {
    guard let id else { return }
    await Task {
      do {
        try await database.endSyncStep(
          id: id, outcome: outcome.rawValue, message: message, succeeded: succeeded,
          failed: failed, at: date)
      } catch {
        Logger.sync.debug("Sync run row \(id) not closed: \(error)")
      }
    }.value
  }
}
