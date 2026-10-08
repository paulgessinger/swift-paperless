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

  // Driven through the database rather than `reconcileDocuments()`, so the
  // stamp is a known value.
  @Test("The store shows the persisted last-refreshed stamp, and follows it when it changes")
  func storeShowsPersistedLastRefreshed() async throws {
    let harness = try await StoreHarness.make()
    #expect(harness.store.lastReconcileAt == nil)

    let first = Date(timeIntervalSince1970: 1_700_000_000)
    try await harness.database.setLastReconcileAt(first, serverID: harness.serverID)
    try await waitUntil({ harness.store.lastReconcileAt == first }, "store never saw the stamp")

    try await harness.database.clearCache()
    try await waitUntil({ harness.store.lastReconcileAt == nil }, "store never saw the reset")
  }

  // MARK: - Background work

  /// A controller that starts in the background and records what reaches the
  /// writer and iOS.
  private func recordingSuspension() -> (DatabaseSuspensionController, () -> [String]) {
    final class Box { var calls: [String] = [] }
    let box = Box()
    let controller = DatabaseSuspensionController(
      isInBackground: true,
      suspend: { box.calls.append("suspend") },
      resume: { box.calls.append("resume") },
      requestTime: { _ in
        box.calls.append("requestTime")
        return { box.calls.append("releaseTime") }
      })
    return (controller, { box.calls })
  }

  @Test("A sync step in the background opens the writer for itself, and closes it when done")
  func syncStepIsBackgroundWork() async throws {
    let (suspension, calls) = recordingSuspension()
    let harness = try await StoreHarness.make(suspension: suspension)

    try await harness.session.syncElements()

    #expect(calls() == ["resume", "requestTime", "suspend", "releaseTime"])
  }

  @Test("Callers joining a step in flight don't count it twice")
  func joinedStepCountsOnce() async throws {
    let (suspension, calls) = recordingSuspension()
    let harness = try await StoreHarness.make(suspension: suspension)

    async let first: Void = harness.session.syncElements()
    async let second: Void = harness.session.syncElements()
    _ = try await (first, second)

    #expect(calls() == ["resume", "requestTime", "suspend", "releaseTime"])
  }

  // The handoff from `DocumentStore.sync()` to its reconcile.
  @Test("A step that starts after the previous one ended opens the writer again")
  func consecutiveStepsEachOpenTheWriter() async throws {
    let (suspension, calls) = recordingSuspension()
    let harness = try await StoreHarness.make(suspension: suspension)

    try await harness.session.syncElements()
    await harness.session.reconcileDocuments(force: true)

    let pass = ["resume", "requestTime", "suspend", "releaseTime"]
    #expect(calls() == pass + pass)
  }

  @Test("The stack hands background-time expiry to its sessions")
  func expiryCancelsSessionWork() async throws {
    let (suspension, _) = recordingSuspension()
    let stack = AppStack(database: try Database.inMemory(), suspension: suspension)
    let session = stack.sessionRegistry.session(for: UUID())
    #expect(suspension.onExpire != nil)

    // Nothing in flight: cancelling is harmless and the session stays usable.
    suspension.expire()
    session.cancelWork()
    #expect(session.syncFailures.isEmpty)
  }

  @Test("A session whose work was called off runs its next step normally")
  func cancelledSessionKeepsWorking() async throws {
    let harness = try await StoreHarness.make()
    _ = try await harness.transient.create(tag: ProtoTag(name: "Receipts", color: tagColor))

    harness.session.cancelWork()
    try await harness.session.syncElements()

    let tags = try await harness.database.elements(TagRecord.self, serverID: harness.serverID)
    #expect(tags.count == 1)
  }
}
