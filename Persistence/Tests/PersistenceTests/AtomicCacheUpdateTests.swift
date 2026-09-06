import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// Covers the two accessors that exist purely to be *one* transaction.
///
/// Both replaced a read-or-write pair in `CachingRepository` that was atomic
/// only because the main actor happened to run the two calls back to back. The
/// `async` accessors suspend, so anything else can now commit in between, and
/// the fix is to push the whole sequence into a single `writer.write`.
///
/// The seam these tests can reach is an in-memory `DatabaseQueue`, which
/// serializes every access — so a genuinely concurrent writer cannot be staged
/// here, and "one transaction" is asserted directly instead, by counting
/// commits through a GRDB `TransactionObserver`. That is the property that
/// closes the window: with one commit there is no point at which another writer
/// could observe or overwrite a half-applied update.
@Suite("AtomicCacheUpdate")
struct AtomicCacheUpdateTests {
  // MARK: - Helpers

  /// Counts committed transactions on a connection, so a test can assert that
  /// an accessor takes exactly one.
  private final class CommitCounter: TransactionObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var _commits = 0

    var commits: Int {
      lock.lock()
      defer { lock.unlock() }
      return _commits
    }

    func reset() {
      lock.lock()
      _commits = 0
      lock.unlock()
    }

    func observes(eventsOfKind _: DatabaseEventKind) -> Bool { true }
    func databaseDidChange(with _: DatabaseEvent) {}
    func databaseDidRollback(_: GRDB.Database) {}

    func databaseDidCommit(_: GRDB.Database) {
      lock.lock()
      _commits += 1
      lock.unlock()
    }
  }

  /// A one-shot flag a `@Sendable` transform can set.
  private final class Ran: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var value: Bool {
      lock.lock()
      defer { lock.unlock() }
      return flag
    }

    func mark() {
      lock.lock()
      flag = true
      lock.unlock()
    }
  }

  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func database(_ server: UUID) throws -> Persistence.Database {
    try Database.seeded(serverID: server)
  }

  /// Attach a commit counter and hand it back zeroed, so the caller measures
  /// only what it does next.
  private func countingCommits(on database: Persistence.Database) throws -> CommitCounter {
    let counter = CommitCounter()
    try database.writer.write { db in
      db.add(transactionObserver: counter, extent: .databaseLifetime)
    }
    counter.reset()
    return counter
  }

  private func doc(_ id: UInt, title: String = "Doc", notesCount: Int = 1) -> Document {
    Document(
      id: id, title: title, created: date(1000), tags: [], owner: .user(1),
      notes: NotesPayload(count: notesCount))
  }

  private func note(_ id: UInt, _ text: String) -> DocumentNote {
    DocumentNote(id: id, note: text, created: date(1000), user: nil)
  }

  private func uiSettings(user: String, appTitle: String?) -> UISettings {
    UISettings(
      user: User(id: 1, isSuperUser: false, username: user, groups: []),
      settings: UISettingsSettings(appTitle: appTitle),
      permissions: UserPermissions.empty(with: { $0.set(.view, to: true, for: .document) }))
  }

  // MARK: - upsertDocumentsInvalidatingNotes

  @Test("upsertDocumentsInvalidatingNotes refreshes the rows and drops their notes")
  func combinedUpsertAndInvalidate() async throws {
    let server = UUID()
    let database = try database(server)

    try await database.upsertDocuments([doc(1), doc(2)], serverID: server)
    try await database.setNotes([note(1, "one")], serverID: server, documentID: 1)
    try await database.setNotes([note(2, "two")], serverID: server, documentID: 2)

    try await database.upsertDocumentsInvalidatingNotes(
      [doc(1, title: "Renamed")], serverID: server)

    #expect(try await database.document(serverID: server, id: 1)?.title == "Renamed")
    #expect(try await database.notes(serverID: server, documentID: 1) == nil)
    // A document outside the batch keeps both its row and its notes.
    #expect(try await database.notes(serverID: server, documentID: 2)?.count == 1)
  }

  @Test("upsertDocumentsInvalidatingNotes takes exactly one transaction")
  func combinedUpsertIsOneTransaction() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.upsertDocuments([doc(1)], serverID: server)
    try await database.setNotes([note(1, "one")], serverID: server, documentID: 1)

    let counter = try countingCommits(on: database)
    try await database.upsertDocumentsInvalidatingNotes([doc(1)], serverID: server)

    // The regression this guards: as two accessors it was two commits, and a
    // `createNote` write-through committing between them was deleted by the
    // invalidation that followed it — invisible under *Recently browsed* until
    // the document was fetched online again.
    #expect(counter.commits == 1)
  }

  @Test("upsertDocumentsInvalidatingNotes writes nothing for an empty batch")
  func combinedUpsertEmptyBatch() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.upsertDocuments([doc(1)], serverID: server)
    try await database.setNotes([note(1, "one")], serverID: server, documentID: 1)

    let counter = try countingCommits(on: database)
    try await database.upsertDocumentsInvalidatingNotes([], serverID: server)

    #expect(counter.commits == 0)
    #expect(try await database.notes(serverID: server, documentID: 1)?.count == 1)
  }

  @Test("upsertDocumentsInvalidatingNotes is scoped to one server")
  func combinedUpsertServerScoping() async throws {
    let serverA = UUID()
    let serverB = UUID()
    let database = try database(serverA)
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "bob")))

    try await database.upsertDocuments([doc(1)], serverID: serverA)
    try await database.upsertDocuments([doc(1)], serverID: serverB)
    try await database.setNotes([note(1, "a")], serverID: serverA, documentID: 1)
    try await database.setNotes([note(1, "b")], serverID: serverB, documentID: 1)

    try await database.upsertDocumentsInvalidatingNotes([doc(1)], serverID: serverA)

    #expect(try await database.notes(serverID: serverA, documentID: 1) == nil)
    #expect(try await database.notes(serverID: serverB, documentID: 1)?.count == 1)
  }

  // MARK: - updateUISettings

  @Test("updateUISettings merges against the row as it stands inside the transaction")
  func updateUISettingsReadsInsideTheTransaction() async throws {
    let server = UUID()
    let database = try database(server)

    try await database.setUISettings(uiSettings(user: "alice", appTitle: "old"), serverID: server)
    // Stands in for an element sync landing a freshly-fetched row. The bug this
    // guards was a read *outside* the write transaction: the merge was built on
    // the row as it looked before this write and put "alice" back.
    try await database.setUISettings(uiSettings(user: "bob", appTitle: "old"), serverID: server)

    let replacement = UISettingsSettings(appTitle: "new")
    let updated = try await database.updateUISettings(serverID: server) { current in
      UISettings(user: current.user, settings: replacement, permissions: current.permissions)
    }

    #expect(updated)
    let stored = try #require(try await database.uiSettings(serverID: server))
    #expect(stored.settings.appTitle == "new")
    #expect(stored.user.username == "bob")
    #expect(stored.permissions.test(.view, for: .document))
  }

  @Test("updateUISettings takes exactly one transaction")
  func updateUISettingsIsOneTransaction() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.setUISettings(uiSettings(user: "alice", appTitle: "old"), serverID: server)

    let counter = try countingCommits(on: database)
    try await database.updateUISettings(serverID: server) { current in
      UISettings(
        user: current.user, settings: UISettingsSettings(appTitle: "new"),
        permissions: current.permissions)
    }

    #expect(counter.commits == 1)
  }

  @Test("updateUISettings reports a missing row and writes nothing")
  func updateUISettingsWithoutARow() async throws {
    let server = UUID()
    let database = try database(server)

    let transformRan = Ran()
    let updated = try await database.updateUISettings(serverID: server) { current in
      transformRan.mark()
      return current
    }

    #expect(!updated)
    #expect(!transformRan.value)
    #expect(try await database.uiSettings(serverID: server) == nil)
  }

  @Test("updateUISettings touches only the named server's row")
  func updateUISettingsServerScoping() async throws {
    let serverA = UUID()
    let serverB = UUID()
    let database = try database(serverA)
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "bob")))

    try await database.setUISettings(uiSettings(user: "alice", appTitle: "a"), serverID: serverA)
    try await database.setUISettings(uiSettings(user: "bob", appTitle: "b"), serverID: serverB)

    try await database.updateUISettings(serverID: serverA) { current in
      UISettings(
        user: current.user, settings: UISettingsSettings(appTitle: "changed"),
        permissions: current.permissions)
    }

    #expect(try await database.uiSettings(serverID: serverA)?.settings.appTitle == "changed")
    #expect(try await database.uiSettings(serverID: serverB)?.settings.appTitle == "b")
  }
}
