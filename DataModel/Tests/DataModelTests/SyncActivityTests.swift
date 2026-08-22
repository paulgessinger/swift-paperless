import Testing

@testable import DataModel

@Suite("SyncActivity")
struct SyncActivityTests {
  private func activity(_ stage: SyncActivity.Stage, completed: Int = 0, total: Int? = nil)
    -> SyncActivity
  {
    SyncActivity(stage: stage, completed: completed, total: total)
  }

  @Test("display order is fixed, not insertion order")
  func orderIsFixed() {
    // The store holds these in a dictionary, so the order it hands over is
    // arbitrary. Whatever arrives, the list must read the same way — a list that
    // reshuffles as each stage reports progress is unreadable.
    let stages: [SyncActivity.Stage] = [.reconcile, .libraryFill, .detailFill]
    #expect(
      stages.map { activity($0) }.sortedForDisplay.map(\.stage) == [
        .libraryFill, .detailFill, .reconcile,
      ])
    #expect(
      stages.reversed().map { activity($0) }.sortedForDisplay.map(\.stage) == [
        .libraryFill, .detailFill, .reconcile,
      ])
  }

  @Test("order covers every stage, so a new one can't silently sort first")
  func orderCoversEveryStage() {
    let sorted = SyncActivity.Stage.allCases.map { activity($0) }.sortedForDisplay
    #expect(sorted.count == SyncActivity.Stage.allCases.count)
    #expect(sorted.map(\.stage) == SyncActivity.Stage.allCases)
  }

  @Test("the overlapping pair reads fill-then-reconcile")
  func overlappingPair() {
    // The combination that actually occurs: `sync()` starts the reconcile in its
    // own task and returns, so a reconcile is still running when a fill begins.
    #expect(
      [activity(.reconcile), activity(.libraryFill)].sortedForDisplay.map(\.stage)
        == [.libraryFill, .reconcile])
  }

  @Test("fraction is nil until a usable total is known")
  func fractionNeedsATotal() {
    #expect(activity(.libraryFill, completed: 3).fraction == nil)
    #expect(activity(.libraryFill, completed: 3, total: 0).fraction == nil)
    #expect(activity(.libraryFill, completed: 3, total: 6).fraction == 0.5)
  }

  @Test("fraction never exceeds 1")
  func fractionClamped() {
    // The delta counts fetched rows against the server's reported total, which
    // can grow under it mid-walk.
    #expect(activity(.reconcile, completed: 12, total: 10).fraction == 1)
  }

  @Test("a stage identifies a row, so progress updates don't re-create it")
  func identityIsTheStage() {
    #expect(activity(.libraryFill, completed: 1, total: 9).id == .libraryFill)
    #expect(
      activity(.libraryFill, completed: 1, total: 9).id
        == activity(.libraryFill, completed: 8, total: 9).id)
  }
}
