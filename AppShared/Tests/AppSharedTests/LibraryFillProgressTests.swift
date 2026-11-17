import DataModel
import Foundation
import Persistence
import Testing

@testable import AppShared

@MainActor
@Suite
struct LibraryFillProgressTests {
  private func entireLibraryHarness(documentCount: Int) async throws -> StoreHarness {
    let harness = try await StoreHarness.make(
      documents: (1...documentCount).map { document(UInt($0)) })
    try harness.database.upsertConnection(
      ConnectionRecord(
        id: harness.serverID,
        url: URL(string: "https://paperless.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "preview"),
        offlineBrowsingMode: "entireLibrary"))
    return harness
  }

  @Test("The library fill reports documents within the view as a page lands")
  func reportsPages() async throws {
    // The transient source serves one page, so this covers a single report.
    let harness = try await entireLibraryHarness(documentCount: 3)
    for id in 1...3 {
      _ = try await harness.transient.update(document: document(UInt(id)))
    }
    let backend = try #require(harness.session.backend)

    var reported: [SyncActivity] = []
    try await backend.fillLibrary(force: true) { activity in
      if let activity { reported.append(activity) }
    }

    let part = SyncActivity.Part(index: 0, count: 1)
    #expect(
      reported.last == SyncActivity(stage: .libraryFill, completed: 3, total: 3, part: part))
    #expect(reported.last?.fraction == 1)
  }

  @Test("A stage that finished is listed as completed until it runs again")
  func completedStages() async throws {
    let harness = try await entireLibraryHarness(documentCount: 3)
    #expect(harness.session.completedSyncStages.isEmpty)

    #expect(await harness.session.fillLibrary(force: true))
    #expect(harness.session.completedSyncStages == [.libraryFill])
    #expect(harness.session.syncActivities.isEmpty)
  }
}
