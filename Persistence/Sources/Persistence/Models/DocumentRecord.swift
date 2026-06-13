import Common
import DataModel
import Foundation
import GRDB

/// Completeness of a cached `document` row (the "tier" from the fetch model).
///
/// `idOnly` is an ordering/membership placeholder (renders a skeleton cell);
/// `metadata` is renderable in a list cell; `detail` carries the full object
/// (custom fields, notes, permissions) fetched when a document is opened.
/// `Comparable` so the non-downgrade upsert can keep the richer of two writes.
public enum DocumentProjection: Int, Codable, Sendable, Comparable {
  case idOnly = 0
  case metadata = 1
  case detail = 2

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// GRDB record for a cached `Document` (`document` table, keyed `(server_id, id)`).
///
/// Bespoke rather than an `ElementRecord`: documents are ordered through
/// `query_order` (never by `name`), carry a projection level, and `Document` is
/// not `Codable` — so the long tail is an explicit storage `Payload`, mapped by
/// hand (the Stage 3 principle: storage shape ≠ wire shape ≠ domain shape).
public struct DocumentRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "document"

  public var serverId: UUID
  public var id: UInt
  public var title: String
  public var asn: UInt?
  public var projectionLevel: DocumentProjection
  public var detailFetchedAt: Date?
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
    // Populated only at `.detail`; preserved across lower-tier upserts.
    public var permissions: Permissions?
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case id
    case title
    case asn
    case projectionLevel = "projection_level"
    case detailFetchedAt = "detail_fetched_at"
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
  public init(serverId: UUID, domain: Document, projectionLevel: DocumentProjection) {
    self.serverId = serverId
    id = domain.id
    title = domain.title
    asn = domain.asn
    self.projectionLevel = projectionLevel
    detailFetchedAt = projectionLevel == .detail ? Date() : nil
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
