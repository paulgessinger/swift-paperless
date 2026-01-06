//
//  NullRepository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.05.2024.
//

import DataModel
import SwiftUI

@MainActor
public class NullRepository: Repository {
  public struct NotImplemented: Error {}

  public init() {}

  public func update(document _: Document) async throws -> Document { throw NotImplemented() }
  public func delete(document _: Document) async throws { throw NotImplemented() }
  public func create(document _: ProtoDocument, file _: URL, filename _: String) async throws {
    throw NotImplemented()
  }

  public func download(documentID _: UInt, progress _: (@Sendable (Double) -> Void)? = nil)
    async throws -> URL?
  { nil }

  public func tag(id _: UInt) async -> Tag? { nil }
  public func create(tag _: ProtoTag) async throws -> Tag { throw NotImplemented() }
  public func update(tag _: Tag) async throws -> Tag { throw NotImplemented() }
  public func delete(tag _: Tag) async throws { throw NotImplemented() }

  public func tags() async -> [Tag] { [] }
  public func uiSettings() async throws -> UISettings {
    UISettings(user: User(id: 0, isSuperUser: false, username: "nobody"), permissions: .empty)
  }

  public func correspondent(id _: UInt) async -> Correspondent? { nil }
  public func create(correspondent _: ProtoCorrespondent) async throws -> Correspondent {
    throw NotImplemented()
  }
  public func update(correspondent _: Correspondent) async throws -> Correspondent {
    throw NotImplemented()
  }
  public func delete(correspondent _: Correspondent) async throws {}

  public func correspondents() async -> [Correspondent] { [] }

  public func documentType(id _: UInt) async -> DocumentType? { nil }
  public func create(documentType _: ProtoDocumentType) async throws -> DocumentType {
    throw NotImplemented()
  }
  public func update(documentType _: DocumentType) async throws -> DocumentType {
    throw NotImplemented()
  }
  public func delete(documentType _: DocumentType) async throws {}
  public func documentTypes() async -> [DocumentType] { [] }

  public func document(id _: UInt) async -> Document? { nil }
  public func document(asn _: UInt) async -> Document? { nil }

  public func metadata(documentId _: UInt) async throws -> Metadata { throw NotImplemented() }

  public func notes(documentId _: UInt) async -> [Document.Note] { [] }
  public func createNote(documentId _: UInt, note _: ProtoDocument.Note) async throws -> [Document
    .Note]
  { [] }
  public func deleteNote(id _: UInt, documentId _: UInt) async throws -> [Document.Note] { [] }

  public nonisolated func documents(filter _: FilterState) -> any DocumentSource {
    NullDocumentSource()
  }

  public func trash() async -> [Document] { [] }
  public func restoreTrash(documents _: [UInt]) async throws {}
  public func emptyTrash(documents _: [UInt]) async throws {}

  public func nextAsn() async -> UInt { 1 }

  public func thumbnail(document _: Document) async -> Image? { nil }
  public func thumbnailData(document _: Document) async throws -> Data { throw NotImplemented() }

  public nonisolated
    func thumbnailRequest(document _: Document) throws -> URLRequest
  { throw NotImplemented() }

  public func savedViews() async -> [SavedView] { [] }
  public func create(savedView _: ProtoSavedView) async throws -> SavedView {
    throw NotImplemented()
  }
  public func update(savedView: SavedView) async throws -> SavedView { savedView }
  public func delete(savedView _: SavedView) async throws { throw NotImplemented() }

  public func storagePaths() async -> [StoragePath] { [] }
  public func create(storagePath _: ProtoStoragePath) async throws -> StoragePath {
    throw NotImplemented()
  }
  public func update(storagePath: StoragePath) async throws -> StoragePath { storagePath }
  public func delete(storagePath _: StoragePath) async throws { throw NotImplemented() }

  public func customFields() async -> [CustomField] { [] }

  public func serverConfiguration() async throws -> ServerConfiguration {
    ServerConfiguration(id: 0, barcodeAsnPrefix: nil)
  }

  public func currentUser() async throws -> User {
    throw NotImplemented()
  }

  public func users() async -> [User] { [] }
  public func groups() async throws -> [UserGroup] { [] }

  public func task(id _: UInt) async throws -> PaperlessTask? { nil }
  public func tasks() async -> [PaperlessTask] { [] }

  public func acknowledge(tasks _: [UInt]) async throws {}

  public func suggestions(documentId _: UInt) async -> Suggestions { .init() }

  public nonisolated
    var delegate: (any URLSessionDelegate)?
  { nil }

  // MARK: - Share links

  public func shareLinks(documentId _: UInt) async throws -> [DataModel.ShareLink] { [] }

  public func create(shareLink _: ProtoShareLink) async throws -> DataModel.ShareLink {
    throw NotImplemented()
  }

  public func delete(shareLink _: DataModel.ShareLink) async throws {
    throw NotImplemented()
  }
}

public actor NullDocumentSource: DocumentSource {
  public func fetch(limit _: UInt) async throws -> [Document] { [] }
  public func hasMore() async -> Bool { false }
}
