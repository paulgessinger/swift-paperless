//
//  DocumentModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation

public protocol DocumentProtocol {
  var documentType: UInt? { get set }
  var asn: UInt? { get set }
  var correspondent: UInt? { get set }
  var tags: [UInt] { get set }
  var storagePath: UInt? { get set }
  var customFields: CustomFieldRawEntryList { get set }
}

public struct NotesPayload: Equatable, Sendable, Hashable {
  public var count: Int = 0

  public init() {}

  public init(count: Int) {
    self.count = count
  }
}

public struct DocumentNote: Identifiable, Equatable, Sendable, Hashable {
  public var id: UInt
  public var note: String
  public var created: Date
  public var user: User?

  public init(id: UInt, note: String, created: Date, user: User? = nil) {
    self.id = id
    self.note = note
    self.created = created
    self.user = user
  }

  // Wire-symmetric leaf value type — round-tripped by ApiDocumentNote and
  // the (future) storage layer. Stays Codable per the Stage 3 principle.
  public struct User: Codable, Equatable, Sendable, Hashable {
    public var id: UInt
    public var username: String

    public init(id: UInt, username: String) {
      self.id = id
      self.username = username
    }
  }
}

public struct Document: Identifiable, Equatable, Hashable, Sendable {
  public var id: UInt
  public var title: String
  public var asn: UInt?
  public var documentType: UInt?
  public var correspondent: UInt?
  public var created: Date
  public var tags: [UInt]
  public var added: Date?
  public var modified: Date?

  // Server's storage filenames for the original (uploaded) and archived
  // (paperless-generated PDF) versions. Optional because older paperless
  // versions or in-progress consumption may omit them.
  public var originalFileName: String?
  public var archivedFileName: String?

  public var storagePath: UInt?
  public var owner: Owner
  public var pageCount: Int?

  public typealias Note = DocumentNote

  public var notes: NotesPayload = .init()
  public var customFields: CustomFieldRawEntryList

  // Presense of this depends on the endpoint
  // If we didn't get a value, we likely just modified
  public private(set) var userCanChange: Bool

  // Presence of this depends on the endpoint
  public var permissions: Permissions? {
    didSet {
      setPermissions = permissions
    }
  }

  // The API wants this extra key for writing perms
  public var setPermissions: Permissions?

  public init(
    id: UInt,
    title: String,
    asn: UInt? = nil,
    documentType: UInt? = nil,
    correspondent: UInt? = nil,
    created: Date,
    tags: [UInt],
    added: Date? = nil,
    modified: Date? = nil,
    originalFileName: String? = nil,
    archivedFileName: String? = nil,
    storagePath: UInt? = nil,
    owner: Owner = .unset,
    pageCount: Int? = nil,
    notes: NotesPayload = .init(),
    customFields: CustomFieldRawEntryList = CustomFieldRawEntryList(),
    userCanChange: Bool = true,
    permissions: Permissions? = nil,
    setPermissions: Permissions? = nil
  ) {
    self.id = id
    self.title = title
    self.asn = asn
    self.documentType = documentType
    self.correspondent = correspondent
    self.created = created
    self.tags = tags
    self.added = added
    self.modified = modified
    self.originalFileName = originalFileName
    self.archivedFileName = archivedFileName
    self.storagePath = storagePath
    self.owner = owner
    self.pageCount = pageCount
    self.notes = notes
    self.customFields = customFields
    self.userCanChange = userCanChange
    self.permissions = permissions
    self.setPermissions = setPermissions
  }
}

extension Document: Model {}
extension Document: DocumentProtocol {}
extension Document: PermissionsModel {}

extension Document {
  /// User-facing filename for exporting/sharing this document. Prefers the
  /// server's stored filename for the requested version; falls back to the
  /// title with a `.pdf` extension, or "document.pdf" if there is no title.
  public func shareFilename(original: Bool) -> String {
    let serverName = original ? originalFileName : archivedFileName
    if let name = serverName, !name.isEmpty { return name }
    let base = title.isEmpty ? "document" : title
    return "\(base).pdf"
  }
}

public struct ProtoDocument: DocumentProtocol, Equatable, Sendable {
  public var title: String
  public var asn: UInt?
  public var documentType: UInt?
  public var correspondent: UInt?
  public var tags: [UInt]
  public var created: Date?
  public var storagePath: UInt?

  public var customFields = CustomFieldRawEntryList()

  public init(
    title: String = "", asn: UInt? = nil, documentType: UInt? = nil, correspondent: UInt? = nil,
    tags: [UInt] = [], created: Date? = .now, storagePath: UInt? = nil
  ) {
    self.title = title
    self.asn = asn
    self.documentType = documentType
    self.correspondent = correspondent
    self.tags = tags
    self.created = created
    self.storagePath = storagePath
  }

  // Inline write-payload helper consumed by `createNote(documentId:note:)`.
  public struct Note: Sendable {
    public var note: String

    public init(note: String) {
      self.note = note
    }
  }
}
