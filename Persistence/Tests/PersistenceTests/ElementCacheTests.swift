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

  // MARK: - Indexing

  @Test("every multi-row element table is indexed on (server_id, name)")
  func elementTablesAreIndexedOnServerAndName() throws {
    let database = try makeDatabase(server: UUID())

    try database.writer.read { db in
      for table in V3_CreateElementCache.multiRowTables {
        let columns = try db.indexes(on: table)
          .first { $0.name == "index_\(table)_on_server_id_name" }?
          .columns
        #expect(columns == ["server_id", "name"], "missing or wrong index on \(table)")
      }
    }
  }

  @Test("the name-ordered collection read sorts via the index, not a temp b-tree")
  func orderedReadUsesTheIndex() async throws {
    let server = UUID()
    let database = try makeDatabase(server: server)
    try await database.replaceElements(
      [tag(1, "B"), tag(2, "A")], of: TagRecord.self, serverID: server)

    let plan = try await database.writer.read { db in
      try String.fetchAll(
        db,
        sql: """
          EXPLAIN QUERY PLAN
          SELECT * FROM tag WHERE server_id = ? ORDER BY name
          """,
        arguments: [server],
        adapter: ColumnMapping(["column": "detail"]))
    }

    // A temp b-tree here would mean the rows were scanned and then sorted.
    #expect(
      !plan.contains { $0.uppercased().contains("USE TEMP B-TREE") },
      "ordered read fell back to a sort: \(plan)")
    #expect(
      plan.contains { $0.contains("index_tag_on_server_id_name") },
      "ordered read did not use the index: \(plan)")
  }

  // MARK: - Round-trip

  @Test("multi-row records round-trip through replace + read")
  func multiRowRoundtrip() async throws {
    let server = UUID()
    let database = try makeDatabase(server: server)

    let tags = [tag(1, "Alpha"), tag(2, "Beta")]
    try await database.replaceElements(tags, of: TagRecord.self, serverID: server)

    let correspondents = [
      Correspondent(
        id: 5, documentCount: 3, lastCorrespondence: nil, name: "ACME",
        slug: "acme", matchingAlgorithm: .literal, match: "x", isInsensitive: false)
    ]
    try await database.replaceElements(
      correspondents, of: CorrespondentRecord.self, serverID: server)

    let customFields = [
      CustomField(
        id: 9, name: "Priority", dataType: .select,
        extraData: .init(
          selectOptions: [.init(id: "a", label: "High")], defaultCurrency: "EUR"),
        documentCount: 2)
    ]
    try await database.replaceElements(
      customFields, of: CustomFieldRecord.self, serverID: server)

    // Tag holds a SwiftUI.Color whose == is provider-identity based, and
    // AppKit's Color→hex conversion drifts ±1 per round-trip on the host — both
    // unrelated to storage. Compare the stable fields; the JSON-column path is
    // proven by the other record types below.
    let fetchedTags = try await database.elements(TagRecord.self, serverID: server)
    #expect(fetchedTags.map(\.id) == tags.map(\.id))
    #expect(fetchedTags.map(\.name) == tags.map(\.name))
    #expect(fetchedTags.map(\.slug) == tags.map(\.slug))
    #expect(fetchedTags.map(\.matchingAlgorithm) == tags.map(\.matchingAlgorithm))

    #expect(
      try await database.elements(CorrespondentRecord.self, serverID: server) == correspondents)
    #expect(
      try await database.elements(CustomFieldRecord.self, serverID: server) == customFields)
  }

  @Test("saved view round-trips its filter rules and permissions")
  func savedViewRoundtrip() async throws {
    let server = UUID()
    let database = try makeDatabase(server: server)

    let view = SavedView(
      id: 3, name: "Inbox", showOnDashboard: true, showInSidebar: false,
      sortField: .created, sortOrder: .descending,
      filterRules: [FilterRule(ruleType: .title, value: .string(value: "invoice"))!],
      owner: .user(1))
    try await database.replaceElements([view], of: SavedViewRecord.self, serverID: server)

    let fetched = try await database.elements(SavedViewRecord.self, serverID: server)
    #expect(fetched == [view])
  }

  // MARK: - Reconcile

  @Test("replaceElements drops rows absent from the new set")
  func replaceDropsMissing() async throws {
    let server = UUID()
    let database = try makeDatabase(server: server)

    try await database.replaceElements(
      [tag(1, "A"), tag(2, "B"), tag(3, "C")], of: TagRecord.self, serverID: server)
    try await database.replaceElements(
      [tag(1, "A"), tag(3, "C-renamed")], of: TagRecord.self, serverID: server)

    let fetched = try await database.elements(TagRecord.self, serverID: server)
    #expect(fetched.map(\.id) == [1, 3])
    #expect(fetched.first { $0.id == 3 }?.name == "C-renamed")
  }

  @Test("replaceElements tolerates the same element twice in one batch")
  func replaceTolerScopesDuplicates() async throws {
    let server = UUID()
    let database = try makeDatabase(server: server)

    // A paginated fetch can yield one element on two consecutive pages when the
    // server deletes a row in between, shifting later elements back a page.
    // `insert` raised a primary-key violation there and rolled the whole
    // reconcile back, losing every other element in the batch.
    let duplicated = [tag(1, "A"), tag(2, "B"), tag(2, "B"), tag(3, "C")]
    try await database.replaceElements(duplicated, of: TagRecord.self, serverID: server)

    let fetched = try await database.elements(TagRecord.self, serverID: server)
    #expect(fetched.map(\.id) == [1, 2, 3])
  }

  @Test("upsert and delete single element")
  func upsertAndDelete() async throws {
    let server = UUID()
    let database = try makeDatabase(server: server)

    try await database.upsertElement(tag(1, "One"), of: TagRecord.self, serverID: server)
    try await database.upsertElement(tag(1, "One-edit"), of: TagRecord.self, serverID: server)
    #expect(try await database.elements(TagRecord.self, serverID: server).first?.name == "One-edit")

    try await database.deleteElement(TagRecord.self, serverID: server, id: 1)
    #expect(try await database.elements(TagRecord.self, serverID: server).isEmpty)
  }

  // MARK: - Scoping & cascade

  @Test("elements are scoped per server")
  func perServerScoping() async throws {
    let serverA = UUID()
    let database = try makeDatabase(server: serverA)
    let serverB = UUID()
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB, url: URL(string: "https://b.example.com/")!,
        user: .init(id: 1, isSuperUser: false, username: "bob")))

    try await database.replaceElements([tag(1, "A")], of: TagRecord.self, serverID: serverA)
    try await database.replaceElements([tag(2, "B")], of: TagRecord.self, serverID: serverB)

    #expect(try await database.elements(TagRecord.self, serverID: serverA).map(\.id) == [1])
    #expect(try await database.elements(TagRecord.self, serverID: serverB).map(\.id) == [2])
  }

  @Test("deleting a server cascades to its element rows")
  func cascadeOnServerDelete() async throws {
    let server = UUID()
    let database = try makeDatabase(server: server)
    try await database.replaceElements(
      [tag(1, "A"), tag(2, "B")], of: TagRecord.self, serverID: server)

    try database.deleteConnection(id: server)

    #expect(try await database.elements(TagRecord.self, serverID: server).isEmpty)
  }

  // MARK: - Singletons

  @Test("server configuration singleton round-trips")
  func serverConfigurationRoundtrip() async throws {
    let server = UUID()
    let database = try makeDatabase(server: server)

    #expect(try await database.serverConfiguration(serverID: server) == nil)
    let config = ServerConfiguration(id: 1, barcodeAsnPrefix: "ASN")
    try await database.setServerConfiguration(config, serverID: server)

    let fetched = try #require(try await database.serverConfiguration(serverID: server))
    #expect(fetched.id == 1)
    #expect(fetched.barcodeAsnPrefix == "ASN")
  }

  @Test("ui settings singleton round-trips user, settings and permissions")
  func uiSettingsRoundtrip() async throws {
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

    try await database.setUISettings(uiSettings, serverID: server)
    let fetched = try #require(try await database.uiSettings(serverID: server))

    #expect(fetched.user == uiSettings.user)
    #expect(fetched.settings == settings)
    #expect(fetched.permissions.test(.view, for: .document))
    #expect(fetched.permissions.test(.change, for: .document))
    #expect(fetched.permissions.test(.view, for: .tag))
    #expect(!fetched.permissions.test(.delete, for: .document))
    #expect(!fetched.permissions.test(.view, for: .correspondent))
  }
}
