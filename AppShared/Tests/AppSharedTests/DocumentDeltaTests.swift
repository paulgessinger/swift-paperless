import DataModel
import Foundation
import Networking
import Persistence
import Testing

@testable import AppShared

@MainActor
@Suite
struct DocumentDeltaTests {
  @Test(
    "The changes pass keeps a new document in either offline mode",
    arguments: ["recentlyBrowsed", "entireLibrary"])
  func keepsNewDocuments(mode: String) async throws {
    var cached = document(100)
    cached.modified = Date(timeIntervalSince1970: 500)
    let harness = try await StoreHarness.make(documents: [cached])
    try harness.database.upsertConnection(
      ConnectionRecord(
        id: harness.serverID,
        url: URL(string: "https://paperless.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "preview"),
        offlineBrowsingMode: mode))
    try await harness.database.setDeltaWatermark(
      Date(timeIntervalSince1970: 400), serverID: harness.serverID)
    try await harness.transient.create(
      document: ProtoDocument(title: "new"), file: URL(filePath: "/dev/null"), filename: "new.pdf")
    let newID = try #require(try await harness.transient.documentIDs(filter: .empty).first)

    let backend = CachingRepository(
      wrapping: harness.transient, database: harness.database, serverID: harness.serverID)
    try await backend.reconcileDocumentChanges()

    #expect(
      try await harness.database.allDocumentIDs(serverID: harness.serverID) == [100, newID])
  }
}
