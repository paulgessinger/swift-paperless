import Testing

@testable import DataModel

@Suite("SyncStep")
struct SyncStepTests {
  private let all = Set(SyncActivity.Stage.allCases)

  private func states(_ steps: [SyncStep]) -> [SyncStep.State] { steps.map(\.state) }

  @Test("order covers every stage")
  func orderCoversEveryStage() {
    #expect(Set(SyncStep.order) == all)
    #expect(SyncStep.order.count == SyncActivity.Stage.allCases.count)
  }

  @Test("nothing reported yet lists every step as pending")
  func allPending() {
    let steps = SyncStep.steps(for: all, activities: [], completed: [])
    #expect(steps.map(\.stage) == SyncStep.order)
    #expect(states(steps).allSatisfy { $0 == .pending })
  }

  @Test("only the stages of the pass are listed")
  func listsOnlyGivenStages() {
    let steps = SyncStep.steps(for: [.reconcile, .elementSync], activities: [], completed: [])
    #expect(steps.map(\.stage) == [.elementSync, .reconcile])
  }

  @Test("overlapping stages both run")
  func overlap() {
    let fill = SyncActivity(stage: .libraryFill, completed: 1, total: 4)
    let steps = SyncStep.steps(
      for: all, activities: [fill, SyncActivity(stage: .reconcile)], completed: [.elementSync])
    #expect(
      states(steps) == [.done, .running, .running, .pending, .pending, .pending])
    #expect(steps[2].activity == fill)
  }

  @Test("a stage skipped without reporting is done once a later one starts")
  func skippedStageIsDone() {
    // The reconcile was throttled and the library is fresh: neither reported.
    let steps = SyncStep.steps(
      for: all, activities: [SyncActivity(stage: .detailFill)], completed: [.elementSync])
    #expect(
      states(steps) == [.done, .done, .done, .running, .pending, .pending])
  }

  @Test("a later stage that finished marks the earlier ones done")
  func completedLaterStage() {
    let steps = SyncStep.steps(for: all, activities: [], completed: [.contentFill])
    #expect(states(steps) == [.done, .done, .done, .done, .done, .pending])
  }
}
