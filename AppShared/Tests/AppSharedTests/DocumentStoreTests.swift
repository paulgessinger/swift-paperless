import DataModel
import Foundation
import Networking
import Persistence
import Testing

@testable import AppShared

@MainActor
@Suite
struct DocumentStoreTests {
  // MARK: - Thumbnails

  @Test("fillIfEnabled runs the files step when the phases include it")
  func fillIfEnabledReachesTheFiles() async throws {
    let lease = await StubDownloadURLProtocol.lease()
    defer { lease.release() }
    StubDownloadURLProtocol.responder = { _ in nil }
    var document = Document(
      id: 1, title: "d1", created: Date(timeIntervalSince1970: 1000), tags: [],
      modified: Date(timeIntervalSince1970: 500), owner: .user(1))
    document.modified = Date(timeIntervalSince1970: 500)
    let harness = try await StoreHarness.make(
      documents: [document], fileDownloader: StoreHarness.stubbedDownloader)
    try harness.database.upsertConnection(
      ConnectionRecord(
        id: harness.serverID, url: URL(string: "https://paperless.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "preview"),
        offlineBrowsingMode: "entireLibrary"))

    await harness.store.fillIfEnabled(phases: [.files])

    let rows = try await harness.database.syncRuns()
    #expect(rows.map(\.step) == ["fileFill"])
    #expect(harness.store.libraryFilesInFlight == 0)  // No registry in a fixture store.
    await harness.fileDownloader?.invalidate()
  }

  @Test("Keeping a document records it and queues its files; the projection follows")
  func keepOfflineQueuesTheArchive() async throws {
    let lease = await StubDownloadURLProtocol.lease()
    defer { lease.release() }
    StubDownloadURLProtocol.responder = { _ in nil }
    var document = document(1)
    document.modified = Date(timeIntervalSince1970: 500)
    let harness = try await StoreHarness.make(
      documents: [document], fileDownloader: StoreHarness.stubbedDownloader)

    try await harness.store.setKeptOffline(1, true)

    #expect(try await harness.database.keptOfflineIDs(serverID: harness.serverID) == [1])
    try await waitUntil({ harness.store.isKeptOffline(1) }, "the projection never saw the pin")
    try await waitUntil(
      { StubDownloadURLProtocol.requests.count == 2 }, "the files were never requested")
    #expect(
      Set(StubDownloadURLProtocol.requests.compactMap(\.url?.path))
        == ["/documents/1/download", "/documents/1/thumb"])
    #expect(
      StubDownloadURLProtocol.requests.allSatisfy {
        $0.allowsExpensiveNetworkAccess && $0.allowsConstrainedNetworkAccess
      })
    let status = try #require(harness.store.makeOfflineStatus())
    try await waitUntil(
      { status.keptOfflineFileProgress.totalDocuments == 1 }, "the status never saw the pin")

    try await harness.store.setKeptOffline(1, false)
    try await waitUntil({ !harness.store.isKeptOffline(1) }, "the projection kept the pin")
    await harness.fileDownloader?.invalidate()
  }

  @Test("Keeping a saved view syncs its list, fetches its members and queues their files")
  func keepSavedViewQueuesTheMembers() async throws {
    let lease = await StubDownloadURLProtocol.lease()
    defer { lease.release() }
    StubDownloadURLProtocol.responder = { _ in nil }
    let harness = try await StoreHarness.make(fileDownloader: StoreHarness.stubbedDownloader)
    for (id, title) in [(1, "invoice a"), (2, "other")] as [(UInt, String)] {
      var document = document(id)
      document.title = title
      document.modified = Date(timeIntervalSince1970: 500)
      _ = try await harness.transient.update(document: document)
    }
    let view = try await harness.transient.create(
      savedView: ProtoSavedView(
        name: "invoices",
        filterRules: [
          try #require(FilterRule(ruleType: .title, value: .string(value: "invoice")))
        ]))
    try await harness.database.upsertElement(
      view, of: SavedViewRecord.self, serverID: harness.serverID)

    #expect(await harness.store.cachedDocumentCount(savedView: view) == nil)

    try await harness.store.setKeptOffline(savedView: view, true)

    #expect(await harness.store.cachedDocumentCount(savedView: view) == 1)

    try await waitUntil(
      { harness.store.isKeptOffline(savedView: view.id) }, "the projection never saw the view")
    #expect(try await harness.database.document(serverID: harness.serverID, id: 1) != nil)
    try await waitUntil({ harness.store.isOnDevice(1) }, "the projection never saw the member")
    #expect(!harness.store.isKeptOffline(1))
    #expect(!harness.store.isOnDevice(2))
    try await waitUntil(
      { StubDownloadURLProtocol.requests.count == 2 }, "the member's files were never requested")
    #expect(
      Set(StubDownloadURLProtocol.requests.compactMap(\.url?.path))
        == ["/documents/1/download", "/documents/1/thumb"])
    #expect(
      StubDownloadURLProtocol.requests.allSatisfy {
        $0.allowsExpensiveNetworkAccess && $0.allowsConstrainedNetworkAccess
      })
    let status = try #require(harness.store.makeOfflineStatus())
    try await waitUntil(
      { status.keptOfflineViewProgress[view.id]?.totalDocuments == 1 },
      "the status never saw the view")
    #expect(status.keptOfflineFileProgress.totalDocuments == 1)

    try await harness.store.setKeptOffline(savedView: view, false)
    try await waitUntil(
      { !harness.store.isKeptOffline(savedView: view.id) }, "the projection kept the view")
    try await waitUntil({ !harness.store.isOnDevice(1) }, "the member stayed on the device")
    await harness.fileDownloader?.invalidate()
  }

  @Test("A thumbnail request is keyed by the session's server and the document's version")
  func thumbnailRequestCarriesTheImageID() async throws {
    let harness = try await StoreHarness.make()

    let request = try harness.store.thumbnailImageRequest(for: document(10))

    #expect(
      request.userInfo[.imageIdKey] as? String
        == ThumbnailImageID.make(serverID: harness.serverID, document: document(10)))
    #expect(request.urlRequest != nil)
  }

  // MARK: - updateDocument

  @Test(
    "updateDocument drops inbox tags only when the server setting asks for it",
    arguments: [true, false])
  func updateDocumentInboxTags(removeInboxTags: Bool) async throws {
    let harness = try await StoreHarness.make(
      tags: [tag(1, inbox: true), tag(2)],
      settings: UISettingsSettings(
        documentEditing: UISettingsDocumentEditing(removeInboxTags: removeInboxTags)))

    let updated = try await harness.store.updateDocument(document(10, tags: [1, 2]))

    #expect(updated.tags == (removeInboxTags ? [2] : [1, 2]))
  }

  @Test("updateDocument emits .changed before the write and .changeReceived after it")
  func updateDocumentEventOrder() async throws {
    let harness = try await StoreHarness.make()
    let events = harness.store.events.subscribe()

    let updated = try await harness.store.updateDocument(document(10))

    var iterator = events.makeAsyncIterator()
    guard case .changed(let sent) = await iterator.next() else {
      Issue.record("first event was not .changed")
      return
    }
    guard case .changeReceived(let received) = await iterator.next() else {
      Issue.record("second event was not .changeReceived")
      return
    }
    #expect(sent.id == 10)
    #expect(received == updated)
  }

  @Test("updateDocument refuses before the request when the user may not change documents")
  func updateDocumentPermissionDenied() async throws {
    let harness = try await StoreHarness.make(
      permissions: .full { $0.set(.change, to: false, for: .document) })
    let events = harness.store.events.subscribe()

    await #expect(throws: PermissionsError.self) {
      try await harness.store.updateDocument(document(10))
    }

    // Nothing was emitted: the refusal comes before `.changed`.
    harness.store.events.finishAll()
    var emitted = 0
    for await _ in events { emitted += 1 }
    #expect(emitted == 0)
  }

  @Test("deleteDocument refuses when the user may not delete documents")
  func deleteDocumentPermissionDenied() async throws {
    let harness = try await StoreHarness.make(
      permissions: .full { $0.set(.delete, to: false, for: .document) })

    await #expect(throws: PermissionsError.self) {
      try await harness.store.deleteDocument(document(10))
    }
  }

  // MARK: - Tag hierarchy

  @Test("tagAncestors walks the parent chain, nearest first, and stops at a cycle")
  func tagAncestors() async throws {
    // 1 ← 2 ← 3, and 5 ↔ 6 form a cycle.
    let harness = try await StoreHarness.make(tags: [
      tag(1), tag(2, parent: 1), tag(3, parent: 2), tag(5, parent: 6), tag(6, parent: 5),
    ])

    #expect(harness.store.tagAncestors(of: 3) == [2, 1])
    #expect(harness.store.tagAncestors(of: 1) == [])
    #expect(harness.store.tagAncestors(of: 5) == [6])
    #expect(harness.store.tagAncestors(of: 99) == [])
  }

  @Test("tagDescendants collects every level below a tag")
  func tagDescendants() async throws {
    // 1 ← 2 ← 3 and 1 ← 4.
    let harness = try await StoreHarness.make(tags: [
      tag(1), tag(2, parent: 1), tag(3, parent: 2), tag(4, parent: 1),
    ])

    #expect(harness.store.tagDescendants(of: 1) == [2, 3, 4])
    #expect(harness.store.tagDescendants(of: 2) == [3])
    #expect(harness.store.tagDescendants(of: 3) == [])
  }

  // MARK: - Sync

  @Test("sync copies the repository's elements into the projection")
  func syncFillsProjection() async throws {
    let harness = try await StoreHarness.make()
    harness.transient.addUser(StoreHarness.user)
    try harness.transient.login(userId: StoreHarness.user.id)
    let created = try await harness.transient.create(
      tag: ProtoTag(name: "Invoices", color: tagColor))

    try await harness.store.sync()

    try await waitUntil({ harness.store.tags[created.id] != nil }, "synced tag never appeared")
    #expect(harness.store.tags[created.id]?.name == "Invoices")
  }
}
