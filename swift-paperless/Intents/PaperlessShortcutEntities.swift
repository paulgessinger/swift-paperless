//
//  PaperlessShortcutEntities.swift
//  swift-paperless
//

import AppIntents
import AppShared
import DataModel
import Foundation

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
      let repository = try await PaperlessIntentRepository.repository()
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
      let repository = try await PaperlessIntentRepository.repository()
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
      let repository = try await PaperlessIntentRepository.repository()
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
