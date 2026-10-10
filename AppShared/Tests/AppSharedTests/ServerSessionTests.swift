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
    #expect(harness.store.lastRefreshedAt == nil)

    let first = Date(timeIntervalSince1970: 1_700_000_000)
    try await harness.database.setLastRefreshedAt(first, serverID: harness.serverID)
    try await waitUntil({ harness.store.lastRefreshedAt == first }, "store never saw the stamp")

    try await harness.database.clearCache()
    try await waitUntil({ harness.store.lastRefreshedAt == nil }, "store never saw the reset")
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

  // MARK: - Cancellation between phases

  /// Records the transient repository's reads, and holds the first document
  /// fetch until released.
  @MainActor
  private final class Traffic {
    var calls: [String] = []
    var fetchReached = false
    var released = false

    func hook(_ name: String) async {
      calls.append(name)
      guard name == "fetch", !fetchReached else { return }
      fetchReached = true
      while !released, !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(2))
      }
    }
  }

  /// A harness whose server fills its entire library, with one document whose
  /// details are still missing, so a completed library fill is followed by a
  /// detail fill.
  private func fillingHarness(_ traffic: Traffic) async throws -> (
    StoreHarness, StoredConnection
  ) {
    let harness = try await StoreHarness.make(documents: [document(1)])
    try harness.database.upsertConnection(
      ConnectionRecord(
        id: harness.serverID,
        url: URL(string: "https://paperless.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "preview"),
        offlineBrowsingMode: "entireLibrary"))
    harness.transient.onRequest = { name in await traffic.hook(name) }
    let stored = StoredConnection(
      id: harness.serverID, url: URL(string: "https://paperless.example.com/api/")!,
      extraHeaders: [], user: StoreHarness.user)
    return (harness, stored)
  }

  @Test("A full pass runs the detail fill after the library fill")
  func passRunsDetailFillAfterLibraryFill() async throws {
    let traffic = Traffic()
    let (harness, stored) = try await fillingHarness(traffic)
    traffic.released = true

    await harness.session.sync(stored: stored, phases: [.fill])

    #expect(traffic.calls.contains("fetch"))
    #expect(traffic.calls.contains("notes") || traffic.calls.contains("metadata"))
  }

  @Test("A pass called off during the library fill never starts the detail fill")
  func cancelledPassStartsNoFurtherPhase() async throws {
    let traffic = Traffic()
    let (harness, stored) = try await fillingHarness(traffic)

    let pass = Task { await harness.session.sync(stored: stored, phases: [.fill]) }
    try await waitUntil({ traffic.fetchReached }, "library fill never reached the network")
    harness.session.cancelWork()
    traffic.released = true
    await pass.value

    #expect(!traffic.calls.contains("notes"))
    #expect(!traffic.calls.contains("metadata"))
  }
}
