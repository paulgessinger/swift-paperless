//
//  PaperlessShortcutEntities.swift
//  swift-paperless
//

import AppIntents
import AppShared
import DataModel
import Foundation

struct PaperlessServerEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Server")
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
  func entities(for identifiers: [PaperlessServerEntity.ID]) async throws -> [PaperlessServerEntity] {
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
    let connectionManager = ConnectionManager()
    let allConnections = Array(connectionManager.connections.values)
    let activeConnectionId = connectionManager.activeConnectionId

    return allConnections
      .sorted {
        if $0.id == activeConnectionId { return true }
        if $1.id == activeConnectionId { return false }
        return $0.shortLabel.localizedCaseInsensitiveCompare($1.shortLabel) == .orderedAscending
      }
      .map { PaperlessServerEntity($0, allConnections: allConnections) }
  }

  @MainActor
  private func activeEntity() -> PaperlessServerEntity? {
    let connectionManager = ConnectionManager()
    guard let activeConnectionId = connectionManager.activeConnectionId,
      let connection = connectionManager.connections[activeConnectionId]
    else {
      return nil
    }

    return PaperlessServerEntity(
      connection,
      allConnections: Array(connectionManager.connections.values))
  }
}

struct PaperlessDocumentTypeEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Document Type")
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
    guard !identifiers.isEmpty else { return [] }
    let ids = Set(identifiers)
    return try await allEntities().filter { ids.contains($0.id) }
  }

  func entities(matching string: String) async throws -> [PaperlessDocumentTypeEntity] {
    let search = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !search.isEmpty else { return try await suggestedEntities() }
    return try await allEntities().filter {
      $0.documentType.name.localizedCaseInsensitiveContains(search)
    }
  }

  func suggestedEntities() async throws -> [PaperlessDocumentTypeEntity] {
    try await allEntities()
  }

  private func allEntities() async throws -> [PaperlessDocumentTypeEntity] {
    do {
      let repository = try await PaperlessIntentRepository.repository(server: intent?.server)
      return try await repository.documentTypes()
        .sortedByLocalizedName()
        .map(PaperlessDocumentTypeEntity.init)
    } catch let error as PaperlessIntentError {
      throw error
    } catch {
      throw PaperlessIntentError.loadOptionsFailed(error.localizedDescription)
    }
  }
}

struct PaperlessCorrespondentEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Correspondent")
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
    guard !identifiers.isEmpty else { return [] }
    let ids = Set(identifiers)
    return try await allEntities().filter { ids.contains($0.id) }
  }

  func entities(matching string: String) async throws -> [PaperlessCorrespondentEntity] {
    let search = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !search.isEmpty else { return try await suggestedEntities() }
    return try await allEntities().filter {
      $0.correspondent.name.localizedCaseInsensitiveContains(search)
    }
  }

  func suggestedEntities() async throws -> [PaperlessCorrespondentEntity] {
    try await allEntities()
  }

  private func allEntities() async throws -> [PaperlessCorrespondentEntity] {
    do {
      let repository = try await PaperlessIntentRepository.repository(server: intent?.server)
      return try await repository.correspondents()
        .sortedByLocalizedName()
        .map(PaperlessCorrespondentEntity.init)
    } catch let error as PaperlessIntentError {
      throw error
    } catch {
      throw PaperlessIntentError.loadOptionsFailed(error.localizedDescription)
    }
  }
}

struct PaperlessTagEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tag")
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
    guard !identifiers.isEmpty else { return [] }
    let ids = Set(identifiers)
    return try await allEntities().filter { ids.contains($0.id) }
  }

  func entities(matching string: String) async throws -> [PaperlessTagEntity] {
    let search = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !search.isEmpty else { return try await suggestedEntities() }
    return try await allEntities().filter {
      $0.tag.name.localizedCaseInsensitiveContains(search)
    }
  }

  func suggestedEntities() async throws -> [PaperlessTagEntity] {
    try await allEntities()
  }

  private func allEntities() async throws -> [PaperlessTagEntity] {
    do {
      let repository = try await PaperlessIntentRepository.repository(server: intent?.server)
      return try await repository.tags()
        .sortedByLocalizedName()
        .map(PaperlessTagEntity.init)
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
