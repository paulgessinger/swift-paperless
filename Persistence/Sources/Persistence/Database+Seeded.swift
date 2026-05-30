import DataModel
import Foundation

extension Database {
  /// Build an in-memory database pre-populated with one server and the given
  /// element rows — the seam previews and tests use instead of injecting a
  /// repository with pre-filled dicts. Under the source-of-truth model every
  /// repository fronts a DB, so a preview's element data lives here and is
  /// surfaced through the same `observe…` live queries as production.
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
    uiSettings: UISettings? = nil,
    serverConfiguration: ServerConfiguration? = nil
  ) throws -> Database {
    let database = try Database.inMemory()
    try database.upsertConnection(
      ConnectionRecord(
        id: serverID,
        url: URL(string: "https://paperless.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "preview")))

    try database.replaceElements(tags, of: TagRecord.self, serverID: serverID)
    try database.replaceElements(correspondents, of: CorrespondentRecord.self, serverID: serverID)
    try database.replaceElements(documentTypes, of: DocumentTypeRecord.self, serverID: serverID)
    try database.replaceElements(storagePaths, of: StoragePathRecord.self, serverID: serverID)
    try database.replaceElements(savedViews, of: SavedViewRecord.self, serverID: serverID)
    try database.replaceElements(users, of: UserRecord.self, serverID: serverID)
    try database.replaceElements(groups, of: UserGroupRecord.self, serverID: serverID)
    try database.replaceElements(customFields, of: CustomFieldRecord.self, serverID: serverID)

    if let uiSettings {
      try database.setUISettings(uiSettings, serverID: serverID)
    }
    if let serverConfiguration {
      try database.setServerConfiguration(serverConfiguration, serverID: serverID)
    }
    return database
  }
}
