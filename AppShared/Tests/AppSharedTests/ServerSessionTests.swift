import DataModel
import Foundation
import Networking
import Persistence
import Testing

@testable import AppShared

@MainActor
@Suite
struct ServerSessionTests {
  @Test("A successful element sync writes the elements to the database and records no failure")
  func syncElementsWritesDatabase() async throws {
    let harness = try await StoreHarness.make()
    harness.transient.addUser(StoreHarness.user)
    try harness.transient.login(userId: StoreHarness.user.id)
    let created = try await harness.transient.create(
      tag: ProtoTag(name: "Receipts", color: tagColor))

    try await harness.session.syncElements()

    let tags = try await harness.database.elements(TagRecord.self, serverID: harness.serverID)
    #expect(tags.map(\.id) == [created.id])
    #expect(harness.session.syncFailures.isEmpty)
  }

  @Test("A ui_settings failure is recorded on its own site and does not fail the element sync")
  func uiSettingsFailureIsNotFatal() async throws {
    let harness = try await StoreHarness.make()
    // No user logged in: `uiSettings()` throws, the element collections don't.
    _ = try await harness.transient.create(tag: ProtoTag(name: "Receipts", color: tagColor))

    try await harness.session.syncElements()

    #expect(harness.session.syncFailures.map(\.site) == [.uiSettings])
    let tags = try await harness.database.elements(TagRecord.self, serverID: harness.serverID)
    #expect(tags.count == 1)
  }
}
