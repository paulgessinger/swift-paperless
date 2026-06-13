import Common
import DataModel
import Foundation
import GRDB

/// One position in a cached query's ordered answer: either the full object (its
/// `document` row is cached) or a **skeleton** (the id is in `query_order` but the
/// object isn't cached yet — rendered as a placeholder). Row existence is the
/// only "loaded-ness" signal; there is no projection level.
public enum DocumentEntry: Sendable, Equatable, Identifiable {
  case loaded(Document)
  case skeleton(id: UInt)

  public var id: UInt {
    switch self {
    case .loaded(let document): document.id
    case .skeleton(let id): id
    }
  }

  /// The object if loaded, else `nil` (a skeleton).
  public var document: Document? {
    if case .loaded(let document) = self { document } else { nil }
  }
}

/// GRDB record for a cached `Document` (`document` table, keyed `(server_id, id)`).
///
/// Bespoke rather than an `ElementRecord`: documents are ordered through
/// `query_order` (never by `name`), and `Document` is not `Codable` — so the long
/// tail is an explicit storage `Payload`, mapped by hand (the Stage 3 principle:
/// storage shape ≠ wire shape ≠ domain shape).
///
/// There is no projection/completeness level: the list always requests
/// `full_perms`, so a stored row is always the complete object. "Loaded-ness" is
/// encoded by **row existence** — a `query_order` id with no `document` row is a
/// skeleton (rendered as a placeholder).
public struct DocumentRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "document"

  public var serverId: UUID
  public var id: UInt
  public var title: String
  public var asn: UInt?
  public var payload: Payload

  /// Storage-local copy of a `DocumentVersion` (decoupled from the domain type
  /// so the on-disk shape doesn't track domain changes).
  public struct VersionPayload: Codable, Sendable, Equatable {
    public var id: UInt
    public var added: Date
    public var label: String?
    public var checksum: String?
    public var isRoot: Bool
  }

  public struct Payload: Codable, Sendable, Equatable {
    public var documentType: UInt?
    public var correspondent: UInt?
    public var created: Date
    public var tags: [UInt]
    public var added: Date?
    public var modified: Date?
    public var originalFileName: String?
    public var archivedFileName: String?
    public var storagePath: UInt?
    public var owner: Owner
    public var pageCount: Int?
    public var notesCount: Int
    public var customFields: CustomFieldRawEntryList
    public var versions: [VersionPayload]
    public var userCanChange: Bool
    // Always populated — the list carries `full_perms`.
    public var permissions: Permissions?
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case id
    case title
    case asn
    case payload = "data"
  }

  // Storage-dedicated JSON coders for the `data` column (sorted keys ⇒
  // deterministic on-disk output), matching the element records.
  public static func databaseJSONEncoder(for column: String) -> JSONEncoder {
    ElementStorage.encoder
  }

  public static func databaseJSONDecoder(for column: String) -> JSONDecoder {
    ElementStorage.decoder
  }
}

extension DocumentRecord {
  public init(serverId: UUID, domain: Document) {
    self.serverId = serverId
    id = domain.id
    title = domain.title
    asn = domain.asn
    payload = Payload(
      documentType: domain.documentType,
      correspondent: domain.correspondent,
      created: domain.created,
      tags: domain.tags,
      added: domain.added,
      modified: domain.modified,
      originalFileName: domain.originalFileName,
      archivedFileName: domain.archivedFileName,
      storagePath: domain.storagePath,
      owner: domain.owner,
      pageCount: domain.pageCount,
      notesCount: domain.notes.count,
      customFields: domain.customFields,
      versions: domain.versions.map {
        VersionPayload(
          id: $0.id, added: $0.added, label: $0.label,
          checksum: $0.checksum, isRoot: $0.isRoot)
      },
      userCanChange: domain.userCanChange,
      permissions: domain.permissions)
  }

  public var domain: Document {
    var document = Document(
      id: id,
      title: title,
      asn: asn,
      documentType: payload.documentType,
      correspondent: payload.correspondent,
      created: payload.created,
      tags: payload.tags,
      added: payload.added,
      modified: payload.modified,
      originalFileName: payload.originalFileName,
      archivedFileName: payload.archivedFileName,
      storagePath: payload.storagePath,
      owner: payload.owner,
      pageCount: payload.pageCount,
      notes: NotesPayload(count: payload.notesCount),
      customFields: payload.customFields,
      versions: payload.versions.map {
        DocumentVersion(
          id: $0.id, added: $0.added, label: $0.label,
          checksum: $0.checksum, isRoot: $0.isRoot)
      },
      userCanChange: payload.userCanChange)
    document.permissions = payload.permissions
    return document
  }
}
