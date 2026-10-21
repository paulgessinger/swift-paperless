//
//  TaskBox.swift
//  AppShared
//

import Foundation
import os

/// A thread-safe holder for a set of long-running `Task`s.
///
/// Exists so an actor-isolated owner can still cancel its tasks from `deinit`,
/// which is nonisolated and therefore cannot read isolated stored properties.
/// Cancellation is safe from any thread; the lock is only here to make the
/// array itself safe to read and replace.
final class TaskBox: Sendable {
  private let tasks = OSAllocatedUnfairLock<[Task<Void, Never>]>(initialState: [])

  /// Cancel whatever is currently held and take ownership of `newTasks`.
  func replace(with newTasks: [Task<Void, Never>]) {
    let previous = tasks.withLock { held -> [Task<Void, Never>] in
      let previous = held
      held = newTasks
      return previous
    }
    for task in previous { task.cancel() }
  }

  /// Cancel and drop everything held.
  func cancelAll() {
    replace(with: [])
  }
}
