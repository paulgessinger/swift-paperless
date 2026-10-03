//
//  PaperlessShortcutEntities.swift
//  swift-paperless
//

import AppIntents
import AppShared
import DataModel
import Foundation
import Networking

struct PaperlessServerEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("entityTypeServer", table: "Intents"))
  static let defaultQuery = PaperlessServerQuery()

  let connection: StoredConnection
  private let title: String
  private let subtitle: String?

  var id: UUID { connection.id }
  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(title)",
      subtitle: subtitle.map { "\($0)" })
  }

  init(_ connection: StoredConnection, allConnections: [StoredConnection]) {
    self.connection = connection

    let isUnique = Self.isServerUnique(connection.url, among: allConnections)
    let urlLabel = isUnique ? connection.shortLabel : connection.label
    let friendlyName = connection.friendlyName?.trimmingCharacters(in: .whitespacesAndNewlines)

    if let friendlyName, !friendlyName.isEmpty {
      title = friendlyName
      subtitle = urlLabel
    } else {
      title = urlLabel
      subtitle = nil
    }
  }

  func matches(_ search: String) -> Bool {
    title.localizedCaseInsensitiveContains(search)
      || subtitle?.localizedCaseInsensitiveContains(search) == true
      || connection.fullLabel.localizedCaseInsensitiveContains(search)
  }

  private static func isServerUnique(_ url: URL, among connections: [StoredConnection]) -> Bool {
    connections.filter { $0.url.absoluteString == url.absoluteString }.count == 1
  }
}

struct PaperlessServerQuery: EntityStringQuery {
  func entities(for identifiers: [PaperlessServerEntity.ID]) async throws -> [PaperlessServerEntity]
  {
    guard !identifiers.isEmpty else { return [] }
    let ids = Set(identifiers)
    return await allEntities().filter { ids.contains($0.id) }
  }

  func entities(matching string: String) async throws -> [PaperlessServerEntity] {
    let search = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !search.isEmpty else { return try await suggestedEntities() }
    return await allEntities().filter { $0.matches(search) }
  }

  func suggestedEntities() async throws -> [PaperlessServerEntity] {
    await allEntities()
  }

  func defaultResult() async -> PaperlessServerEntity? {
    await activeEntity()
  }

  @MainActor
  private func allEntities() -> [PaperlessServerEntity] {
    let connectionManager = PaperlessIntentStore.connectionManager
    let allConnections = Array(connectionManager.connections.values)
    let activeConnectionId = connectionManager.activeConnectionId

    return
      allConnections
      .sorted {
        if $0.id == activeConnectionId { return true }
        if $1.id == activeConnectionId { return false }
        return $0.shortLabel.localizedCaseInsensitiveCompare($1.shortLabel) == .orderedAscending
      }
      .map { PaperlessServerEntity($0, allConnections: allConnections) }
  }

  @MainActor
  private func activeEntity() -> PaperlessServerEntity? {
    let connectionManager = PaperlessIntentStore.connectionManager
    guard let connection = connectionManager.storedConnection else {
      return nil
    }

    return PaperlessServerEntity(
      connection,
      allConnections: Array(connectionManager.connections.values))
  }
}

struct PaperlessDocumentTypeEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("entityTypeDocumentType", table: "Intents"))
  static let defaultQuery = PaperlessDocumentTypeQuery()

  let documentType: DocumentType

  var id: Int { Int(documentType.id) }
  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(documentType.name)")
  }

  init(_ documentType: DocumentType) {
    self.documentType = documentType
  }
}

struct PaperlessDocumentTypeQuery: EntityStringQuery {
  @IntentParameterDependency<UploadDocumentIntent>(\.$server)
  private var intent

  func entities(for identifiers: [PaperlessDocumentTypeEntity.ID]) async throws
    -> [PaperlessDocumentTypeEntity]
  {
    try await PaperlessElementLoader.resolve(
      identifiers, server: intent?.server, kind: String(localized: .app(.documentType))
    ) { try await $0.documentTypes() }
    .map(PaperlessDocumentTypeEntity.init)
  }

  func entities(matching string: String) async throws -> [PaperlessDocumentTypeEntity] {
    let search = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return try await suggestedEntities().filter {
      search.isEmpty || $0.documentType.name.localizedCaseInsensitiveContains(search)
    }
  }

  func suggestedEntities() async throws -> [PaperlessDocumentTypeEntity] {
    try await PaperlessElementLoader.suggested(server: intent?.server) {
      try await $0.documentTypes()
    }
    .map(PaperlessDocumentTypeEntity.init)
  }
}

struct PaperlessCorrespondentEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("entityTypeCorrespondent", table: "Intents"))
  static let defaultQuery = PaperlessCorrespondentQuery()

  let correspondent: Correspondent

  var id: Int { Int(correspondent.id) }
  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(correspondent.name)")
  }

  init(_ correspondent: Correspondent) {
    self.correspondent = correspondent
  }
}

struct PaperlessCorrespondentQuery: EntityStringQuery {
  @IntentParameterDependency<UploadDocumentIntent>(\.$server)
  private var intent

  func entities(for identifiers: [PaperlessCorrespondentEntity.ID]) async throws
    -> [PaperlessCorrespondentEntity]
  {
    try await PaperlessElementLoader.resolve(
      identifiers, server: intent?.server, kind: String(localized: .app(.correspondent))
    ) { try await $0.correspondents() }
    .map(PaperlessCorrespondentEntity.init)
  }

  func entities(matching string: String) async throws -> [PaperlessCorrespondentEntity] {
    let search = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return try await suggestedEntities().filter {
      search.isEmpty || $0.correspondent.name.localizedCaseInsensitiveContains(search)
    }
  }

  func suggestedEntities() async throws -> [PaperlessCorrespondentEntity] {
    try await PaperlessElementLoader.suggested(server: intent?.server) {
      try await $0.correspondents()
    }
    .map(PaperlessCorrespondentEntity.init)
  }
}

struct PaperlessTagEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("entityTypeTag", table: "Intents"))
  static let defaultQuery = PaperlessTagQuery()

  let tag: Tag

  var id: Int { Int(tag.id) }
  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(tag.name)")
  }

  init(_ tag: Tag) {
    self.tag = tag
  }
}

struct PaperlessTagQuery: EntityStringQuery {
  @IntentParameterDependency<UploadDocumentIntent>(\.$server)
  private var intent

  func entities(for identifiers: [PaperlessTagEntity.ID]) async throws -> [PaperlessTagEntity] {
    try await PaperlessElementLoader.resolve(
      identifiers, server: intent?.server, kind: String(localized: .app(.tag))
    ) { try await $0.tags() }
    .map(PaperlessTagEntity.init)
  }

  func entities(matching string: String) async throws -> [PaperlessTagEntity] {
    let search = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return try await suggestedEntities().filter {
      search.isEmpty || $0.tag.name.localizedCaseInsensitiveContains(search)
    }
  }

  func suggestedEntities() async throws -> [PaperlessTagEntity] {
    try await PaperlessElementLoader.suggested(server: intent?.server) { try await $0.tags() }
      .map(PaperlessTagEntity.init)
  }
}

/// Element reads for the server picked in the intent (or the active one), always
/// through the store's repository so they come from the synced local cache.
@MainActor
private enum PaperlessElementLoader {
  /// Picker lists: read the cache, syncing only when it has nothing to show.
  ///
  /// Every keystroke in the Shortcuts editor lands here — `entities(matching:)`
  /// filters this list rather than querying its own — so the path has to stay
  /// cheap enough to run per character. A cache read is; a sync is not, being a
  /// `ui_settings` fetch plus every element collection, unthrottled (the
  /// single-flight in `syncElements` only merges *concurrent* callers), and
  /// blind to the `syncOverCellular` gate that `SyncEngine` weighs for its own
  /// sweeps. Keeping this cache current is that engine's job, together with the
  /// app's foreground sync for the active server.
  ///
  /// An empty cache is the one case that cannot wait for either: a picker with
  /// no rows is useless, and the server may have been added moments ago. That
  /// alone pays for a bounded sync.
  static func suggested<Element: LocallyNamed & Sendable>(
    server: PaperlessServerEntity?,
    load: @Sendable (any Repository) async throws -> [Element]
  ) async throws -> [Element] {
    try await loading {
      let store = try await PaperlessIntentStore.store(server: server)
      let cached = try await load(store.repository)
      guard cached.isEmpty else {
        return cached.sortedByLocalizedName()
      }
      await store.sync(timeout: .seconds(3))
      return try await load(store.repository).sortedByLocalizedName()
    }
  }

  /// Saved parameter values: read the cache without syncing. Only if an ID is
  /// missing, sync once and read again before reporting it as gone.
  static func resolve<Element: Identifiable & Sendable>(
    _ identifiers: [Int],
    server: PaperlessServerEntity?,
    kind: String,
    load: @Sendable (any Repository) async throws -> [Element]
  ) async throws -> [Element] where Element.ID == UInt {
    guard !identifiers.isEmpty else { return [] }
    let ids = Set(identifiers)
    return try await loading {
      let store = try await PaperlessIntentStore.store(server: server)
      var found = try await load(store.repository).filter { ids.contains(Int($0.id)) }
      if found.count < ids.count {
        try? await store.sync()
        found = try await load(store.repository).filter { ids.contains(Int($0.id)) }
        guard found.count == ids.count else {
          throw PaperlessIntentError.missingElement(kind)
        }
      }
      return found
    }
  }

  private static func loading<T>(_ body: () async throws -> T) async throws -> T {
    do {
      return try await body()
    } catch let error as PaperlessIntentError {
      throw error
    } catch {
      throw PaperlessIntentError.loadOptionsFailed(error.localizedDescription)
    }
  }
}

private protocol LocallyNamed {
  var name: String { get }
}

extension DocumentType: LocallyNamed {}
extension Correspondent: LocallyNamed {}
extension Tag: LocallyNamed {}

extension Array where Element: LocallyNamed {
  fileprivate func sortedByLocalizedName() -> [Element] {
    sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }
}
