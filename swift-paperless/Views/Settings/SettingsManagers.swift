//
//  SettingsManagers.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.09.23.
//

import DataModel
import Foundation
import SwiftUI

// MARK: - Tag Management

extension TagView: RowViewProtocol {
  typealias Element = Tag

  @MainActor
  init(element: Tag) {
    self.init(tag: element)
  }
}

extension TagEditView: EditViewProtocol where Element == Tag {}

extension TagEditView: CreateViewProtocol where Element == ProtoTag {}

struct TagManager: ManagerProtocol {
  final class Model: ManagerModel {
    typealias Element = Tag
    typealias ProtoElement = ProtoTag

    private let store: DocumentStore

    init(store: DocumentStore) {
      self.store = store
    }

    func load() -> [Element] {
      store.tags
        .values
        .sorted(by: {
          $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
    }

    func update(_ tag: Tag) async throws {
      try await store.update(tag: tag)
    }

    func create(_ tag: ProtoTag) async throws -> Tag {
      try await store.create(tag: tag)
    }

    func delete(_ tag: Tag) async throws {
      try await store.delete(tag: tag)
    }

    @MainActor
    var permissions: UserPermissions.PermissionSet {
      store.permissions[.tag]
    }
  }

  static var elementName: KeyPath<Tag, String> { \.name }

  typealias RowView = TagView
  typealias EditView = TagEditView<Tag>
  typealias CreateView = TagEditView<ProtoTag>
}

// MARK: - Correspondent Management

extension CorrespondentEditView: EditViewProtocol where Element == Correspondent {}

extension CorrespondentEditView: CreateViewProtocol where Element == ProtoCorrespondent {}

struct CorrespondentManager: ManagerProtocol {
  static var elementName: KeyPath<Correspondent, String> { \.name }

  final class Model: ManagerModel {
    typealias Element = Correspondent
    typealias ProtoElement = ProtoCorrespondent

    private let store: DocumentStore

    init(store: DocumentStore) {
      self.store = store
    }

    func load() -> [Element] {
      store.correspondents
        .values
        .sorted(by: {
          $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
    }

    func update(_ correspondent: Correspondent) async throws {
      try await store.update(correspondent: correspondent)
    }

    func create(_ correspondent: ProtoCorrespondent) async throws -> Correspondent {
      try await store.create(correspondent: correspondent)
    }

    func delete(_ correspondent: Correspondent) async throws {
      try await store.delete(correspondent: correspondent)
    }

    @MainActor
    var permissions: UserPermissions.PermissionSet {
      store.permissions[.correspondent]
    }
  }

  typealias EditView = CorrespondentEditView<Correspondent>
  typealias CreateView = CorrespondentEditView<ProtoCorrespondent>

  struct RowView: RowViewProtocol {
    var element: Correspondent

    var body: some View {
      Text(element.name)
    }
  }
}

// MARK: - Document Type Management

extension DocumentTypeEditView: EditViewProtocol where Element == DocumentType {}

extension DocumentTypeEditView: CreateViewProtocol where Element == ProtoDocumentType {}

struct DocumentTypeManager: ManagerProtocol {
  static var elementName: KeyPath<Model.Element, String> { \.name }

  final class Model: ManagerModel {
    typealias Element = DocumentType
    typealias ProtoElement = ProtoDocumentType

    private let store: DocumentStore

    init(store: DocumentStore) {
      self.store = store
    }

    func load() -> [Element] {
      store.documentTypes
        .values
        .sorted(by: {
          $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
    }

    func update(_ dt: DocumentType) async throws {
      try await store.update(documentType: dt)
    }

    func create(_ dt: ProtoDocumentType) async throws -> DocumentType {
      try await store.create(documentType: dt)
    }

    func delete(_ dt: DocumentType) async throws {
      try await store.delete(documentType: dt)
    }

    @MainActor
    var permissions: UserPermissions.PermissionSet {
      store.permissions[.documentType]
    }
  }

  typealias EditView = DocumentTypeEditView<DocumentType>
  typealias CreateView = DocumentTypeEditView<ProtoDocumentType>

  struct RowView: RowViewProtocol {
    var element: DocumentType

    var body: some View {
      Text(element.name)
    }
  }
}

// MARK: - Saved View Management

extension SavedViewEditView: EditViewProtocol where Element == SavedView {}

extension SavedViewEditView: CreateViewProtocol where Element == ProtoSavedView {}

struct SavedViewManager: ManagerProtocol {
  static var elementName: KeyPath<SavedView, String> { \.name }

  final class Model: ManagerModel {
    typealias Element = SavedView
    typealias ProtoElement = ProtoSavedView

    private let store: DocumentStore

    init(store: DocumentStore) {
      self.store = store
    }

    func load() -> [SavedView] {
      store.savedViews
        .values
        .sorted(by: {
          $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
    }

    func update(_ view: SavedView) async throws {
      try await store.update(savedView: view)
    }

    func create(_ view: ProtoSavedView) async throws -> SavedView {
      try await store.create(savedView: view)
    }

    func delete(_ view: SavedView) async throws {
      try await store.delete(savedView: view)
    }

    @MainActor
    var permissions: UserPermissions.PermissionSet {
      store.permissions[.savedView]
    }
  }

  typealias EditView = SavedViewEditView<SavedView>
  typealias CreateView = SavedViewEditView<ProtoSavedView>

  struct RowView: RowViewProtocol {
    var element: SavedView

    var body: some View {
      Text(element.name)
    }
  }
}

// MARK: - Storage Paths Management

extension StoragePathEditView: EditViewProtocol where Element == StoragePath {}

extension StoragePathEditView: CreateViewProtocol where Element == ProtoStoragePath {}

struct StoragePathManager: ManagerProtocol {
  static var elementName: KeyPath<StoragePath, String> { \.name }

  final class Model: ManagerModel {
    typealias Element = StoragePath
    typealias ProtoElement = ProtoStoragePath

    private let store: DocumentStore

    init(store: DocumentStore) {
      self.store = store
    }

    func load() -> [StoragePath] {
      store.storagePaths.values
        .sorted(by: {
          $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
    }

    func update(_ path: StoragePath) async throws {
      try await store.update(storagePath: path)
    }

    func create(_ path: ProtoStoragePath) async throws -> StoragePath {
      try await store.create(storagePath: path)
    }

    func delete(_ path: StoragePath) async throws {
      try await store.delete(storagePath: path)
    }

    @MainActor
    var permissions: UserPermissions.PermissionSet {
      store.permissions[.storagePath]
    }
  }

  typealias EditView = StoragePathEditView<StoragePath>
  typealias CreateView = StoragePathEditView<ProtoStoragePath>

  struct RowView: RowViewProtocol {
    var element: StoragePath

    var body: some View {
      Text(element.name)
    }
  }
}
