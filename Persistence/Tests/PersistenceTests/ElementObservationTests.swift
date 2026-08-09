import DataModel
import Foundation
import Testing

@testable import Persistence

@Suite("ElementObservation")
struct ElementObservationTests {
  // MARK: - Helpers

  private struct TimeoutError: Error {}

  /// First emission of a stream, with a timeout so a missing/never-firing
  /// observation fails the test instead of hanging.
  private func firstValue<T: Sendable>(
    from stream: AsyncThrowingStream<T, Error>
  ) async throws -> T {
    try await withTimeout {
      var iterator = stream.makeAsyncIterator()
      guard let value = try await iterator.next() else { throw TimeoutError() }
      return value
    }
  }

  /// The emission that lands *after* `action` runs. Consumes the initial value
  /// first (which also guarantees the observation is subscribed before the
  /// write), runs `action`, then returns the next emission.
  private func value<T: Sendable>(
    from stream: AsyncThrowingStream<T, Error>,
    afterSubscribe action: @escaping @Sendable () async throws -> Void
  ) async throws -> T {
    try await withTimeout {
      var iterator = stream.makeAsyncIterator()
      _ = try await iterator.next()
      try await action()
      guard let value = try await iterator.next() else { throw TimeoutError() }
      return value
    }
  }

  private func withTimeout<T: Sendable>(
    seconds: Double = 3,
    _ operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(for: .seconds(seconds))
        throw TimeoutError()
      }
      let result = try await group.next()!
      group.cancelAll()
      return result
    }
  }

  private func correspondent(_ id: UInt, _ name: String) -> Correspondent {
    Correspondent(
      id: id, documentCount: 0, lastCorrespondence: nil, name: name,
      slug: name.lowercased(), matchingAlgorithm: .auto, match: "", isInsensitive: true)
  }

  // MARK: - Tests

  @Test("observeElements emits the current state on subscribe, name-ordered")
  func emitsInitialState() async throws {
    let server = UUID()
    let database = try Database.seeded(
      serverID: server, correspondents: [correspondent(2, "Beta"), correspondent(1, "Alpha")])

    let initial = try await firstValue(
      from: database.observeElements(CorrespondentRecord.self, serverID: server))
    #expect(initial.map(\.name) == ["Alpha", "Beta"])
  }

  @Test("observeElements re-emits after an upsert write-through")
  func emitsAfterUpsert() async throws {
    let server = UUID()
    let database = try Database.seeded(
      serverID: server, correspondents: [correspondent(1, "Alpha")])

    let updated = try await value(
      from: database.observeElements(CorrespondentRecord.self, serverID: server)
    ) {
      try database.upsertElement(
        self.correspondent(2, "Beta"), of: CorrespondentRecord.self, serverID: server)
    }
    #expect(updated.map(\.id) == [1, 2])
  }

  @Test("observeElements re-emits after a delete")
  func emitsAfterDelete() async throws {
    let server = UUID()
    let database = try Database.seeded(
      serverID: server, correspondents: [correspondent(1, "Alpha"), correspondent(2, "Beta")])

    let remaining = try await value(
      from: database.observeElements(CorrespondentRecord.self, serverID: server)
    ) {
      try database.deleteElement(CorrespondentRecord.self, serverID: server, id: 1)
    }
    #expect(remaining.map(\.id) == [2])
  }

  @Test("observeUISettings emits nil cold, then the value after setUISettings")
  func uiSettingsColdThenSet() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    let cold = try await firstValue(from: database.observeUISettings(serverID: server))
    #expect(cold == nil)

    let settings = UISettings(
      user: User(id: 7, isSuperUser: false, username: "alice", groups: []),
      settings: UISettingsSettings(),
      permissions: .empty)
    let resolved = try await value(from: database.observeUISettings(serverID: server)) {
      try database.setUISettings(settings, serverID: server)
    }
    #expect(resolved?.user.id == 7)
    #expect(resolved?.user.username == "alice")
  }

  @Test("observeServerConfiguration emits nil cold, then the value after set")
  func serverConfigurationColdThenSet() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    let cold = try await firstValue(from: database.observeServerConfiguration(serverID: server))
    #expect(cold == nil)

    let resolved = try await value(
      from: database.observeServerConfiguration(serverID: server)
    ) {
      try database.setServerConfiguration(
        ServerConfiguration(id: 1, barcodeAsnPrefix: "ASN"), serverID: server)
    }
    #expect(resolved?.barcodeAsnPrefix == "ASN")
  }

  @Test("observeElements is scoped to its server")
  func scopedPerServer() async throws {
    let serverA = UUID()
    let database = try Database.seeded(serverID: serverA, correspondents: [correspondent(1, "A")])
    let serverB = UUID()
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB, url: URL(string: "https://b.example.com/")!,
        user: .init(id: 1, isSuperUser: false, username: "bob")))
    try database.replaceElements(
      [correspondent(2, "B")], of: CorrespondentRecord.self, serverID: serverB)

    let aOnly = try await firstValue(
      from: database.observeElements(CorrespondentRecord.self, serverID: serverA))
    #expect(aOnly.map(\.id) == [1])
  }
}
