import Common
import DataModel
import Foundation
import GRDB
import SwiftUI
import Testing

@testable import Persistence

@Suite("ElementCache")
struct ElementCacheTests {
  // MARK: - Helpers

  private func makeDatabase(server: UUID) throws -> Persistence.Database {
    let database = try Persistence.Database.inMemory()
    let record = ConnectionRecord(
      id: server,
      url: URL(string: "https://paperless.example.com/api/")!,
      user: .init(id: 1, isSuperUser: true, username: "alice"))
    try database.upsertConnection(record)
    return database
  }

  private func tag(_ id: UInt, _ name: String) -> DataModel.Tag {
    DataModel.Tag(
      id: id, isInboxTag: false, name: name, slug: name.lowercased(),
      color: Color(hex: "#3366cc")!.hex, match: "m", matchingAlgorithm: .auto,
      isInsensitive: true, parent: nil)
  }

  // MARK: - Round-trip

  @Test("multi-row records round-trip through replace + read")
  func multiRowRoundtrip() throws {
    let server = UUID()
    let database = try makeDatabase(server: server)

    let tags = [tag(1, "Alpha"), tag(2, "Beta")]
    try database.replaceElements(tags, of: TagRecord.self, serverID: server)

    let correspondents = [
      Correspondent(
        id: 5, documentCount: 3, lastCorrespondence: nil, name: "ACME",
        slug: "acme", matchingAlgorithm: .literal, match: "x", isInsensitive: false)
    ]
    try database.replaceElements(
      correspondents, of: CorrespondentRecord.self, serverID: server)

    let customFields = [
      CustomField(
        id: 9, name: "Priority", dataType: .select,
        extraData: .init(
          selectOptions: [.init(id: "a", label: "High")], defaultCurrency: "EUR"),
        documentCount: 2)
    ]
    try database.replaceElements(
      customFields, of: CustomFieldRecord.self, serverID: server)

    // Tag holds a SwiftUI.Color whose == is provider-identity based, and
    // AppKit's Color→hex conversion drifts ±1 per round-trip on the host — both
    // unrelated to storage. Compare the stable fields; the JSON-column path is
    // proven by the other record types below.
    let fetchedTags = try database.elements(TagRecord.self, serverID: server)
    #expect(fetchedTags.map(\.id) == tags.map(\.id))
    #expect(fetchedTags.map(\.name) == tags.map(\.name))
    #expect(fetchedTags.map(\.slug) == tags.map(\.slug))
    #expect(fetchedTags.map(\.matchingAlgorithm) == tags.map(\.matchingAlgorithm))

    #expect(
      try database.elements(CorrespondentRecord.self, serverID: server) == correspondents)
    #expect(
      try database.elements(CustomFieldRecord.self, serverID: server) == customFields)
  }

  @Test("saved view round-trips its filter rules and permissions")
  func savedViewRoundtrip() throws {
    let server = UUID()
    let database = try makeDatabase(server: server)

    let view = SavedView(
      id: 3, name: "Inbox", showOnDashboard: true, showInSidebar: false,
      sortField: .created, sortOrder: .descending,
      filterRules: [FilterRule(ruleType: .title, value: .string(value: "invoice"))!],
      owner: .user(1))
    try database.replaceElements([view], of: SavedViewRecord.self, serverID: server)

    let fetched = try database.elements(SavedViewRecord.self, serverID: server)
    #expect(fetched == [view])
  }

  // MARK: - Reconcile

  @Test("replaceElements drops rows absent from the new set")
  func replaceDropsMissing() throws {
    let server = UUID()
    let database = try makeDatabase(server: server)

    try database.replaceElements(
      [tag(1, "A"), tag(2, "B"), tag(3, "C")], of: TagRecord.self, serverID: server)
    try database.replaceElements(
      [tag(1, "A"), tag(3, "C-renamed")], of: TagRecord.self, serverID: server)

    let fetched = try database.elements(TagRecord.self, serverID: server)
    #expect(fetched.map(\.id) == [1, 3])
    #expect(fetched.first { $0.id == 3 }?.name == "C-renamed")
  }

  @Test("upsert and delete single element")
  func upsertAndDelete() throws {
    let server = UUID()
    let database = try makeDatabase(server: server)

    try database.upsertElement(tag(1, "One"), of: TagRecord.self, serverID: server)
    try database.upsertElement(tag(1, "One-edit"), of: TagRecord.self, serverID: server)
    #expect(try database.elements(TagRecord.self, serverID: server).first?.name == "One-edit")

    try database.deleteElement(TagRecord.self, serverID: server, id: 1)
    #expect(try database.elements(TagRecord.self, serverID: server).isEmpty)
  }

  // MARK: - Scoping & cascade

  @Test("elements are scoped per server")
  func perServerScoping() throws {
    let serverA = UUID()
    let database = try makeDatabase(server: serverA)
    let serverB = UUID()
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB, url: URL(string: "https://b.example.com/")!,
        user: .init(id: 1, isSuperUser: false, username: "bob")))

    try database.replaceElements([tag(1, "A")], of: TagRecord.self, serverID: serverA)
    try database.replaceElements([tag(2, "B")], of: TagRecord.self, serverID: serverB)

    #expect(try database.elements(TagRecord.self, serverID: serverA).map(\.id) == [1])
    #expect(try database.elements(TagRecord.self, serverID: serverB).map(\.id) == [2])
  }

  @Test("deleting a server cascades to its element rows")
  func cascadeOnServerDelete() throws {
    let server = UUID()
    let database = try makeDatabase(server: server)
    try database.replaceElements(
      [tag(1, "A"), tag(2, "B")], of: TagRecord.self, serverID: server)

    try database.deleteConnection(id: server)

    #expect(try database.elements(TagRecord.self, serverID: server).isEmpty)
  }

  // MARK: - Singletons

  @Test("server configuration singleton round-trips")
  func serverConfigurationRoundtrip() throws {
    let server = UUID()
    let database = try makeDatabase(server: server)

    #expect(try database.serverConfiguration(serverID: server) == nil)
    let config = ServerConfiguration(id: 1, barcodeAsnPrefix: "ASN")
    try database.setServerConfiguration(config, serverID: server)

    let fetched = try #require(try database.serverConfiguration(serverID: server))
    #expect(fetched.id == 1)
    #expect(fetched.barcodeAsnPrefix == "ASN")
  }

  @Test("ui settings singleton round-trips user, settings and permissions")
  func uiSettingsRoundtrip() throws {
    let server = UUID()
    let database = try makeDatabase(server: server)

    let permissions = UserPermissions.empty(with: {
      $0.set(.view, to: true, for: .document)
      $0.set(.change, to: true, for: .document)
      $0.set(.view, to: true, for: .tag)
    })
    let settings = UISettingsSettings(
      documentEditing: .init(removeInboxTags: true),
      permissions: .init(defaultOwner: 1, defaultViewUsers: [2, 3]),
      savedViews: .init(dashboardViewsVisibleIds: [9]),
      appTitle: "My Paperless")
    let uiSettings = UISettings(
      user: User(id: 1, isSuperUser: false, username: "alice", groups: [7]),
      settings: settings,
      permissions: permissions)

    try database.setUISettings(uiSettings, serverID: server)
    let fetched = try #require(try database.uiSettings(serverID: server))

    #expect(fetched.user == uiSettings.user)
    #expect(fetched.settings == settings)
    #expect(fetched.permissions.test(.view, for: .document))
    #expect(fetched.permissions.test(.change, for: .document))
    #expect(fetched.permissions.test(.view, for: .tag))
    #expect(!fetched.permissions.test(.delete, for: .document))
    #expect(!fetched.permissions.test(.view, for: .correspondent))
  }

  // MARK: - Observation

  @Test("observeElements fires on an element write")
  func observationFires() async throws {
    let server = UUID()
    let database = try makeDatabase(server: server)
    let stream = database.observeElements()

    try database.replaceElements([tag(1, "A")], of: TagRecord.self, serverID: server)

    let change = await withThrowingTaskGroup(of: CacheChange?.self) { group in
      group.addTask {
        for await change in stream { return change }
        return nil
      }
      group.addTask {
        try await Task.sleep(for: .seconds(2))
        return nil
      }
      let first = try? await group.next()
      group.cancelAll()
      return first ?? nil
    }

    #expect(change == .elements(kinds: Set(ElementKind.allCases)))
  }
}
