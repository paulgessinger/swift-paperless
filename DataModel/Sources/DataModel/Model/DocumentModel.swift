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
  /// The notes themselves, when the response carried them (paperless-ngx 2.15
  /// and later); `nil` when it carried only their ids.
  public var notes: [DocumentNote]?

  public init() {}

  public init(count: Int) {
    self.count = count
  }

  public init(notes: [DocumentNote]) {
    count = notes.count
    self.notes = notes
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
  // the (future) storage layer. Stays Codable: wire, storage and domain
  // shapes coincide here.
  public struct User: Codable, Equatable, Sendable, Hashable {
    public var id: UInt
    public var username: String

    public init(id: UInt, username: String) {
      self.id = id
      self.username = username
    }
  }
}

public struct DocumentVersion: Identifiable, Equatable, Sendable, Hashable {
  public var id: UInt
  public var added: Date
  public var label: String?
  public var checksum: String?
  public var isRoot: Bool

  public init(
    id: UInt, added: Date, label: String? = nil,
    checksum: String? = nil, isRoot: Bool
  ) {
    self.id = id
    self.added = added
    self.label = label
    self.checksum = checksum
    self.isRoot = isRoot
  }
}

public struct DocumentDuplicate: Identifiable, Equatable, Hashable, Sendable {
  public var id: UInt
  public var title: String
  /// Set when the duplicate is in the trash.
  public var deletedAt: Date?

  public init(id: UInt, title: String, deletedAt: Date? = nil) {
    self.id = id
    self.title = title
    self.deletedAt = deletedAt
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

  // Server-side version rows for this document. The serializer sorts these
  // id-descending (newest first), but nothing here relies on that — the
  // accessors below order explicitly. Empty on backends predating
  // multi-version support, which means anything before v3.0.0-beta.
  // `currentVersionID` and `rootVersionID` resolve the right id even when this
  // is empty by falling back to `self.id` — the document id equals the root
  // version id on the server (versions are sibling rows in the same table).
  public var versions: [DocumentVersion] = []

  // Presence of this depends on the endpoint
  public var permissions: Permissions? {
    didSet {
      setPermissions = permissions
    }
  }

  // The API wants this extra key for writing perms
  public var setPermissions: Permissions?

  // Other documents with the same file content that the user can view. Only a
  // single-document fetch fills this in, and it is not cached: `nil` means
  // unknown, not "no duplicates".
  public var duplicates: [DocumentDuplicate]?

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
    versions: [DocumentVersion] = [],
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
    self.versions = versions
    self.permissions = permissions
    self.setPermissions = setPermissions
  }
}

extension Document: Model {}
extension Document: DocumentProtocol {}
extension Document: PermissionsModel {}

extension Document {
  /// Filename for sharing this document, built the way paperless-ngx names its
  /// downloads: `"{created} {correspondent} {title}"` plus the extension (see
  /// `Document.get_public_filename` upstream). It is rebuilt from current
  /// metadata rather than taken from `archivedFileName`, which goes stale when
  /// a correspondent is renamed: that does not bump the document's `modified`.
  ///
  /// A document without an archive version is served as its original for an
  /// archive request, so it takes the original's extension. The original's
  /// extension comes from its upload name; with none, the name has no extension.
  public func shareFilename(original: Bool, correspondentName: String?) -> String {
    let fileExtension: String
    if !original, archivedFileName != nil {
      fileExtension = ".pdf"
    } else if let ext = originalFileName.map({ ($0 as NSString).pathExtension }), !ext.isEmpty {
      fileExtension = ".\(ext)"
    } else {
      fileExtension = ""
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let day = calendar.dateComponents([.year, .month, .day], from: created)
    var head = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    if let correspondentName, !correspondentName.isEmpty { head += " \(correspondentName)" }
    if !title.isEmpty { head += " \(title)" }

    // paperless caps the name at 255 UTF-8 bytes, shortening the head first.
    let headBudget = max(0, 255 - fileExtension.utf8.count)
    while head.utf8.count > headBudget { head.removeLast() }

    // pathvalidate's universal rules: replace characters invalid on any
    // platform, and trim the spaces Windows rejects at either end.
    let invalid: Set<Unicode.Scalar> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
    let sanitized = String(
      String.UnicodeScalarView(
        (head + fileExtension).unicodeScalars.map {
          invalid.contains($0) || $0.value < 0x20 || $0.value == 0x7F ? "-" : $0
        }))
    return sanitized.trimmingCharacters(in: .whitespaces)
  }

  /// Id of the version the server returns when no `?version=` query is sent.
  /// paperless resolves that with `order_by("-id").first()`, so we order by
  /// id too — *not* by `added`, which can disagree after an import or restore
  /// preserves original timestamps. Ids are unique primary keys, so this
  /// ordering is total and the result never depends on array order.
  ///
  /// Falls back to `self.id` when `versions` is empty (older backends,
  /// single-file documents) — the document id equals the root version id
  /// server-side, so this fallback is correct, not a fudge.
  public var currentVersionID: UInt {
    versions.max(by: { $0.id < $1.id })?.id ?? id
  }

  /// Version id to put in a `?version=` query, or `nil` when the parameter
  /// should be omitted entirely.
  ///
  /// With no versions, `currentVersionID` is `self.id` — the root id, which is
  /// exactly what the backend picks anyway, so sending it conveys nothing.
  /// Omitting it keeps request URLs byte-identical to what pre-versions builds
  /// sent, which matters because Nuke keys its thumbnail data cache on the URL
  /// string: sending a redundant parameter would invalidate every cached
  /// thumbnail for every user whose server has no multi-version support.
  public var versionQueryID: UInt? {
    versions.isEmpty ? nil : currentVersionID
  }

  /// Id of the original/root version. Same fallback rationale as
  /// `currentVersionID`.
  public var rootVersionID: UInt {
    versions.first(where: \.isRoot)?.id ?? id
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
