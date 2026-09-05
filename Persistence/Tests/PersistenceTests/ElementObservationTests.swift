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

  /// Per-server narrowing probe: subscribe, run `foreignWrite` (a write for
  /// *another* server, which the observation's table region cannot exclude),
  /// give the observation time to process it, then run `ownWrite` and return
  /// the next emission.
  ///
  /// If the foreign write leaked an emission, that stale value — not the one
  /// `ownWrite` produced — is what comes back, so the caller's expectation on
  /// the returned value is the assertion. Sequencing the own write behind the
  /// foreign one also proves the stream is still live, i.e. the silence was
  /// narrowing and not a dead subscription.
  private func valueSkippingForeignWrite<T: Sendable>(
    from stream: AsyncThrowingStream<T, Error>,
    foreignWrite: @escaping @Sendable () async throws -> Void,
    ownWrite: @escaping @Sendable () async throws -> Void
  ) async throws -> T {
    try await withTimeout {
      var iterator = stream.makeAsyncIterator()
      _ = try await iterator.next()
      try await foreignWrite()
      // Long enough for the observation to have fetched and (had it not been
      // de-duplicated) emitted before the own write lands, so the two writes
      // cannot be coalesced into one notification.
      try await Task.sleep(for: .milliseconds(250))
      try await ownWrite()
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

  /// Registers a second server so its rows satisfy the `server_id` foreign key.
  @discardableResult
  private func addServer(to database: Database, host: String) throws -> UUID {
    let id = UUID()
    try database.upsertConnection(
      ConnectionRecord(
        id: id, url: URL(string: "https://\(host).example.com/")!,
        user: .init(id: 1, isSuperUser: false, username: host)))
    return id
  }

  private func uiSettings(_ id: UInt, _ username: String) -> UISettings {
    UISettings(
      user: User(id: id, isSuperUser: false, username: username, groups: []),
      settings: UISettingsSettings(),
      permissions: .empty)
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
      try await database.upsertElement(
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
      try await database.deleteElement(CorrespondentRecord.self, serverID: server, id: 1)
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
      try await database.setUISettings(settings, serverID: server)
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
      try await database.setServerConfiguration(
        ServerConfiguration(id: 1, barcodeAsnPrefix: "ASN"), serverID: server)
    }
    #expect(resolved?.barcodeAsnPrefix == "ASN")
  }

  @Test("observeElements is scoped to its server")
  func scopedPerServer() async throws {
    let serverA = UUID()
    let database = try Database.seeded(serverID: serverA, correspondents: [correspondent(1, "A")])
    let serverB = try addServer(to: database, host: "b")
    try await database.replaceElements(
      [correspondent(2, "B")], of: CorrespondentRecord.self, serverID: serverB)

    let aOnly = try await firstValue(
      from: database.observeElements(CorrespondentRecord.self, serverID: serverA))
    #expect(aOnly.map(\.id) == [1])
  }

  // MARK: - Per-server narrowing (#696)

  @Test("observeElements does not emit for another server's write")
  func elementsIgnoreForeignServerWrite() async throws {
    let serverA = UUID()
    let database = try Database.seeded(serverID: serverA, correspondents: [correspondent(1, "A")])
    let serverB = try addServer(to: database, host: "b")

    let next = try await valueSkippingForeignWrite(
      from: database.observeElements(CorrespondentRecord.self, serverID: serverA),
      foreignWrite: {
        try await database.replaceElements(
          [self.correspondent(50, "Foreign")], of: CorrespondentRecord.self, serverID: serverB)
        try await database.deleteElement(CorrespondentRecord.self, serverID: serverB, id: 50)
      },
      ownWrite: {
        try await database.upsertElement(
          self.correspondent(2, "Beta"), of: CorrespondentRecord.self, serverID: serverA)
      })
    #expect(next.map(\.id) == [1, 2])
  }

  @Test("observeElements does not re-emit an identical own-server write")
  func elementsIgnoreIdenticalWrite() async throws {
    let serverA = UUID()
    let database = try Database.seeded(serverID: serverA, correspondents: [correspondent(1, "A")])

    let next = try await valueSkippingForeignWrite(
      from: database.observeElements(CorrespondentRecord.self, serverID: serverA),
      foreignWrite: {
        // Same rows, written again: a fresh transaction, an identical result.
        try await database.replaceElements(
          [self.correspondent(1, "A")], of: CorrespondentRecord.self, serverID: serverA)
      },
      ownWrite: {
        try await database.upsertElement(
          self.correspondent(2, "Beta"), of: CorrespondentRecord.self, serverID: serverA)
      })
    #expect(next.map(\.id) == [1, 2])
  }

  @Test("observeUISettings does not emit for another server's write")
  func uiSettingsIgnoreForeignServerWrite() async throws {
    let serverA = UUID()
    let database = try Database.seeded(serverID: serverA)
    let serverB = try addServer(to: database, host: "b")

    let next = try await valueSkippingForeignWrite(
      from: database.observeUISettings(serverID: serverA),
      foreignWrite: {
        try await database.setUISettings(self.uiSettings(9, "bob"), serverID: serverB)
      },
      ownWrite: { try await database.setUISettings(self.uiSettings(7, "alice"), serverID: serverA) }
    )
    #expect(next?.user.username == "alice")
  }

  @Test("observeServerConfiguration does not emit for another server's write")
  func serverConfigurationIgnoresForeignServerWrite() async throws {
    let serverA = UUID()
    let database = try Database.seeded(serverID: serverA)
    let serverB = try addServer(to: database, host: "b")

    let next = try await valueSkippingForeignWrite(
      from: database.observeServerConfiguration(serverID: serverA),
      foreignWrite: {
        try await database.setServerConfiguration(
          ServerConfiguration(id: 1, barcodeAsnPrefix: "FOREIGN"), serverID: serverB)
      },
      ownWrite: {
        try await database.setServerConfiguration(
          ServerConfiguration(id: 1, barcodeAsnPrefix: "ASN"), serverID: serverA)
      })
    #expect(next?.barcodeAsnPrefix == "ASN")
  }
}
