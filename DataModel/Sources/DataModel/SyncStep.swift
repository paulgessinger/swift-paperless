//
//  SyncStep.swift
//  DataModel
//

import Foundation

/// One step of a sync pass as the Offline & Sync screen lists it: every step
/// of the pass is listed from the start, and moves from pending to running to
/// done.
public struct SyncStep: Sendable, Equatable, Identifiable {
  public enum State: Sendable, Equatable {
    case pending, running, done
  }

  public var id: SyncActivity.Stage { stage }

  public var stage: SyncActivity.Stage
  public var state: State
  /// The stage's progress while it runs.
  public var activity: SyncActivity?

  public init(stage: SyncActivity.Stage, state: State, activity: SyncActivity? = nil) {
    self.stage = stage
    self.state = state
    self.activity = activity
  }

  /// The order a pass lists its steps in. The file downloads go last: they
  /// outlast the step that queued them.
  public static let order: [SyncActivity.Stage] = [
    .elementSync, .reconcile, .libraryFill, .detailFill, .contentFill, .fileDownload,
  ]

  /// The steps of a pass, in ``order``.
  ///
  /// A stage that neither runs nor finished counts as done once a later one
  /// has started: a pass skips a stage with nothing to do without reporting
  /// it.
  ///
  /// - Parameters:
  ///   - stages: The stages the pass covers.
  ///   - activities: The stages running now.
  ///   - completed: The stages that finished in this pass.
  public static func steps(
    for stages: Set<SyncActivity.Stage>, activities: [SyncActivity],
    completed: Set<SyncActivity.Stage>
  ) -> [SyncStep] {
    let listed = order.filter(stages.contains)
    let running = Dictionary(
      activities.map { ($0.stage, $0) }, uniquingKeysWith: { first, _ in first })
    let lastStarted = listed.lastIndex { running[$0] != nil || completed.contains($0) }
    return listed.enumerated().map { index, stage in
      if let activity = running[stage] {
        return SyncStep(stage: stage, state: .running, activity: activity)
      }
      let passed = lastStarted.map { index < $0 } ?? false
      return SyncStep(stage: stage, state: completed.contains(stage) || passed ? .done : .pending)
    }
  }
}
