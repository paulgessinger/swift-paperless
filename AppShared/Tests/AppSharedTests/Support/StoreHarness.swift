import Common
import DataModel
import Foundation
import Networking
import Persistence
import SwiftUI
import Testing

@testable import AppShared

// The SDK 27 SwiftUI declares top-level `Tag` and `Document` types, which makes
// the unqualified names ambiguous wherever SwiftUI and DataModel are both
// imported.
typealias Tag = DataModel.Tag
typealias Document = DataModel.Document

/// A `DocumentStore` wired the way production wires one, over an in-memory
/// database: `TransientRepository` → `CachingRepository` → `ServerSession` →
/// `DocumentStore`.
///
/// The database is seeded directly, so the store's projection sees `tags`,
/// `documents` and the `ui_settings` row without a sync. The projection reads
/// them through GRDB observations, which deliver on a later main-actor hop;
/// ``make(tags:documents:permissions:settings:)`` waits for the permission
/// matrix to land so tests start from a hydrated store.
@MainActor
struct StoreHarness {
  nonisolated static let user = User(id: 1, isSuperUser: false, username: "tester")

  let serverID: UUID
  let database: Database
  let transient: TransientRepository
  let session: ServerSession
  let store: DocumentStore

  static func make(
    tags: [Tag] = [],
    documents: [Document] = [],
    permissions: UserPermissions = .full,
    settings: UISettingsSettings = UISettingsSettings(),
    suspension: DatabaseSuspensionController? = nil
  ) async throws -> StoreHarness {
    let serverID = UUID()
    let database = try Database.seeded(
      serverID: serverID,
      tags: tags,
      documents: documents,
      uiSettings: UISettings(user: user, settings: settings, permissions: permissions))
    let transient = TransientRepository()
    // The app-group content store blocks on a macOS host; the reconcile's
    // reclaim gets one in a temporary directory instead.
    let contentRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("StoreHarness-\(UUID().uuidString)")
    let caching = CachingRepository(
      wrapping: transient, database: database, serverID: serverID,
      contentStore: { try? ContentStore(root: contentRoot) })
    let session = ServerSession(serverID: serverID, repository: caching, suspension: suspension)
    let store = DocumentStore(session: session)
    try await waitUntil({ store.permissionsKnown }, "projection never hydrated")
    if !tags.isEmpty {
      try await waitUntil({ store.tags.count == tags.count }, "projection never saw the tags")
    }
    return StoreHarness(
      serverID: serverID, database: database, transient: transient, session: session,
      store: store)
  }
}

/// Polls `condition` on the main actor until it holds. Records an issue and
/// returns if it does not hold within five seconds.
@MainActor
func waitUntil(
  _ condition: () -> Bool,
  _ comment: Comment? = nil,
  sourceLocation: SourceLocation = #_sourceLocation
) async throws {
  let deadline = ContinuousClock.now + .seconds(5)
  while !condition() {
    if ContinuousClock.now > deadline {
      Issue.record(comment ?? "timed out waiting for condition", sourceLocation: sourceLocation)
      return
    }
    try await Task.sleep(for: .milliseconds(2))
  }
}

/// A fixed sRGB color. `Color.gray`, the `Tag`/`ProtoTag` default, is a dynamic
/// catalog color on macOS that `HexColor` cannot encode.
let tagColor = Color(hex: "#3366cc")!.hex

func tag(_ id: UInt, parent: UInt? = nil, inbox: Bool = false) -> Tag {
  Tag(
    id: id, isInboxTag: inbox, name: "tag \(id)", slug: "tag-\(id)",
    color: tagColor, match: "", matchingAlgorithm: .none,
    isInsensitive: true, parent: parent)
}

func document(_ id: UInt, tags: [UInt] = []) -> Document {
  Document(
    id: id, title: "document \(id)", created: Date(timeIntervalSince1970: 1000), tags: tags,
    owner: .user(StoreHarness.user.id))
}
