import DataModel
import Foundation
import Testing

@testable import AppShared

@MainActor
@Suite
struct UploadDefaultsTests {
  @Test("Changes are written through, and the last one wins")
  func writesThrough() async throws {
    let harness = try await StoreHarness.make()
    let defaults = try #require(await harness.store.loadUploadDefaults())
    #expect(defaults.serverID == harness.serverID)
    #expect(defaults.tags.isEmpty)

    defaults.tags = [1]
    defaults.tags = [1, 2]
    defaults.tags = [2, 3]
    await defaults.saveTask?.value

    let reloaded = try #require(await harness.store.loadUploadDefaults())
    #expect(reloaded.tags == [2, 3])
  }

  @Test("existingTags drops the tags the server does not have, keeping the order")
  func existingTagsDropsUnknownIds() {
    let known = [1: tag(1), 2: tag(2)] as [UInt: Tag]
    #expect(UploadDefaults.existingTags([2, 99, 1], in: known) == [2, 1])
  }

  @Test("existingTags keeps everything while no tags are loaded")
  func existingTagsWithoutTags() {
    #expect(UploadDefaults.existingTags([2, 99], in: [:]) == [2, 99])
  }
}
