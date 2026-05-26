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

extension TagView: RowViewProtocol where Trailing == EmptyView {
  public typealias Element = Tag

  @MainActor
  public init(element: Tag) {
    self.init(tag: element)
  }
}

extension TagEditView: EditViewProtocol where Element == Tag {}

extension TagEditView: CreateViewProtocol where Element == ProtoTag {}

public struct TagManager: ManagerProtocol {
  public final class Model: ManagerModel {
    public typealias Element = Tag
    public typealias ProtoElement = ProtoTag

    private let store: DocumentStore

    public init(store: DocumentStore) {
      self.store = store
    }

    public func load() -> [Element] {
      store.tags
        .values
        .sorted(by: {
          $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
    }

    public func hierarchy() -> [HierarchyNode<Tag>]? {
      let all = load()
      guard all.contains(where: { $0.parent != nil }) else { return nil }

      let known = Set(all.map(\.id))
      var byParent: [UInt?: [Tag]] = [:]
      for tag in all {
        // Treat references to unknown/inaccessible parents as roots so no tag is hidden.
        let key: UInt? = tag.parent.flatMap { known.contains($0) ? $0 : nil }
        byParent[key, default: []].append(tag)
      }

      func build(parent: UInt?) -> [HierarchyNode<Tag>] {
        (byParent[parent] ?? []).map { tag in
          let children = build(parent: tag.id)
          return HierarchyNode(element: tag, children: children.isEmpty ? nil : children)
        }
      }

      return build(parent: nil)
    }

    public func update(_ tag: Tag) async throws {
      try await store.update(tag: tag)
    }

    public func create(_ tag: ProtoTag) async throws -> Tag {
      try await store.create(tag: tag)
    }

    public func delete(_ tag: Tag) async throws {
      try await store.delete(tag: tag)
    }

    @MainActor
    public var permissions: UserPermissions.PermissionSet {
      store.permissions[.tag]
    }
  }

  public static var elementName: KeyPath<Tag, String> { \.name }

  public typealias RowView = TagView<EmptyView>
  public typealias EditView = TagEditView<Tag>
  public typealias CreateView = TagEditView<ProtoTag>
}

// MARK: - Correspondent Management

extension CorrespondentEditView: EditViewProtocol where Element == Correspondent {}

extension CorrespondentEditView: CreateViewProtocol where Element == ProtoCorrespondent {}

public struct CorrespondentManager: ManagerProtocol {
  public static var elementName: KeyPath<Correspondent, String> { \.name }

  public final class Model: ManagerModel {
    public typealias Element = Correspondent
    public typealias ProtoElement = ProtoCorrespondent

    private let store: DocumentStore

    public init(store: DocumentStore) {
      self.store = store
    }

    public func load() -> [Element] {
      store.correspondents
        .values
        .sorted(by: {
          $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
    }

    public func update(_ correspondent: Correspondent) async throws {
      try await store.update(correspondent: correspondent)
    }

    public func create(_ correspondent: ProtoCorrespondent) async throws -> Correspondent {
      try await store.create(correspondent: correspondent)
    }

    public func delete(_ correspondent: Correspondent) async throws {
      try await store.delete(correspondent: correspondent)
    }

    @MainActor
    public var permissions: UserPermissions.PermissionSet {
      store.permissions[.correspondent]
    }
  }

  public typealias EditView = CorrespondentEditView<Correspondent>
  public typealias CreateView = CorrespondentEditView<ProtoCorrespondent>

  public struct RowView: RowViewProtocol {
    var element: Correspondent
    public init(element: Correspondent) { self.element = element }

    public var body: some View {
      Text(element.name)
    }
  }
}

// MARK: - Document Type Management

extension DocumentTypeEditView: EditViewProtocol where Element == DocumentType {}

extension DocumentTypeEditView: CreateViewProtocol where Element == ProtoDocumentType {}

public struct DocumentTypeManager: ManagerProtocol {
  public static var elementName: KeyPath<Model.Element, String> { \.name }

  public final class Model: ManagerModel {
    public typealias Element = DocumentType
    public typealias ProtoElement = ProtoDocumentType

    private let store: DocumentStore

    public init(store: DocumentStore) {
      self.store = store
    }

    public func load() -> [Element] {
      store.documentTypes
        .values
        .sorted(by: {
          $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
    }

    public func update(_ dt: DocumentType) async throws {
      try await store.update(documentType: dt)
    }

    public func create(_ dt: ProtoDocumentType) async throws -> DocumentType {
      try await store.create(documentType: dt)
    }

    public func delete(_ dt: DocumentType) async throws {
      try await store.delete(documentType: dt)
    }

    @MainActor
    public var permissions: UserPermissions.PermissionSet {
      store.permissions[.documentType]
    }
  }

  public typealias EditView = DocumentTypeEditView<DocumentType>
  public typealias CreateView = DocumentTypeEditView<ProtoDocumentType>

  public struct RowView: RowViewProtocol {
    var element: DocumentType
    public init(element: DocumentType) { self.element = element }

    public var body: some View {
      Text(element.name)
    }
  }
}

// MARK: - Saved View Management

extension SavedViewEditView: EditViewProtocol where Element == SavedView {}

extension SavedViewEditView: CreateViewProtocol where Element == ProtoSavedView {}

public struct SavedViewManager: ManagerProtocol {
  public static var elementName: KeyPath<SavedView, String> { \.name }

  public final class Model: ManagerModel {
    public typealias Element = SavedView
    public typealias ProtoElement = ProtoSavedView

    private let store: DocumentStore

    public init(store: DocumentStore) {
      self.store = store
    }

    public func load() -> [SavedView] {
      store.savedViews
        .values
        .sorted(by: {
          $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
    }

    public func update(_ view: SavedView) async throws {
      try await store.update(savedView: view)
    }

    public func create(_ view: ProtoSavedView) async throws -> SavedView {
      try await store.create(savedView: view)
    }

    public func delete(_ view: SavedView) async throws {
      try await store.delete(savedView: view)
    }

    @MainActor
    public var permissions: UserPermissions.PermissionSet {
      store.permissions[.savedView]
    }
  }

  public typealias EditView = SavedViewEditView<SavedView>
  public typealias CreateView = SavedViewEditView<ProtoSavedView>

  public struct RowView: RowViewProtocol {
    var element: SavedView
    public init(element: SavedView) { self.element = element }

    public var body: some View {
      Text(element.name)
    }
  }
}

// MARK: - Storage Paths Management

extension StoragePathEditView: EditViewProtocol where Element == StoragePath {}

extension StoragePathEditView: CreateViewProtocol where Element == ProtoStoragePath {}

public struct StoragePathManager: ManagerProtocol {
  public static var elementName: KeyPath<StoragePath, String> { \.name }

  public final class Model: ManagerModel {
    public typealias Element = StoragePath
    public typealias ProtoElement = ProtoStoragePath

    private let store: DocumentStore

    public init(store: DocumentStore) {
      self.store = store
    }

    public func load() -> [StoragePath] {
      store.storagePaths.values
        .sorted(by: {
          $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
    }

    public func update(_ path: StoragePath) async throws {
      try await store.update(storagePath: path)
    }

    public func create(_ path: ProtoStoragePath) async throws -> StoragePath {
      try await store.create(storagePath: path)
    }

    public func delete(_ path: StoragePath) async throws {
      try await store.delete(storagePath: path)
    }

    @MainActor
    public var permissions: UserPermissions.PermissionSet {
      store.permissions[.storagePath]
    }
  }

  public typealias EditView = StoragePathEditView<StoragePath>
  public typealias CreateView = StoragePathEditView<ProtoStoragePath>

  public struct RowView: RowViewProtocol {
    var element: StoragePath
    public init(element: StoragePath) { self.element = element }

    public var body: some View {
      Text(element.name)
    }
  }
}
