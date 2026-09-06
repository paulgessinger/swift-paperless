import DataModel
import Foundation
import GRDB

extension Database {
  /// Build an in-memory database pre-populated with one server and the given
  /// element rows — the seam previews and tests use instead of injecting a
  /// repository with pre-filled dicts. Under the source-of-truth model every
  /// repository fronts a DB, so a preview's element data lives here and is
  /// surfaced through the same `observe…` live queries as production.
  ///
  /// Stays synchronous — a SwiftUI preview builds its store in a property
  /// initializer and cannot await — without needing blocking cache accessors:
  /// the cache tables are `async` only outside the package (see the rule in
  /// `Database+Connections`), but seeding lives *inside* it, so it composes the
  /// same `static` query bodies those accessors use into one `writer.write`.
  /// One transaction rather than a dozen is the right shape for a seed anyway.
  ///
  /// Mirrors the inline `makeDatabase` helper in `ElementCacheTests`.
  public static func seeded(
    serverID: UUID = UUID(),
    tags: [Tag] = [],
    correspondents: [Correspondent] = [],
    documentTypes: [DocumentType] = [],
    storagePaths: [StoragePath] = [],
    savedViews: [SavedView] = [],
    users: [User] = [],
    groups: [UserGroup] = [],
    customFields: [CustomField] = [],
    documents: [Document] = [],
    uiSettings: UISettings? = nil,
    serverConfiguration: ServerConfiguration? = nil
  ) throws -> Database {
    let database = try Database.inMemory()
    // `server` is the one table with a blocking accessor, and this row has to
    // exist before the cache rows that FK-reference it.
    try database.upsertConnection(
      ConnectionRecord(
        id: serverID,
        url: URL(string: "https://paperless.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "preview")))

    try database.wrapping("seeded") {
      try database.writer.write { db in
        try writeElements(tags, of: TagRecord.self, serverID: serverID, db)
        try writeElements(correspondents, of: CorrespondentRecord.self, serverID: serverID, db)
        try writeElements(documentTypes, of: DocumentTypeRecord.self, serverID: serverID, db)
        try writeElements(storagePaths, of: StoragePathRecord.self, serverID: serverID, db)
        try writeElements(savedViews, of: SavedViewRecord.self, serverID: serverID, db)
        try writeElements(users, of: UserRecord.self, serverID: serverID, db)
        try writeElements(groups, of: UserGroupRecord.self, serverID: serverID, db)
        try writeElements(customFields, of: CustomFieldRecord.self, serverID: serverID, db)

        try writeDocumentRows(db, documents, serverID: serverID)

        if let uiSettings {
          try writeUISettings(uiSettings, serverID: serverID, db)
        }
        if let serverConfiguration {
          try writeServerConfiguration(serverConfiguration, serverID: serverID, db)
        }
      }
    }
    return database
  }
}
