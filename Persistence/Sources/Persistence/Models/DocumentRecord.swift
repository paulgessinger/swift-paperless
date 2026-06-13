import Common
import DataModel
import Foundation
import GRDB

/// Completeness of a cached `document` row.
///
/// Two states, because the document list now always requests `full_perms`, so a
/// list row carries the same object as a single-document fetch — there's no
/// poorer "metadata" tier to distinguish:
/// - `idOnly` — an ordering/membership placeholder: the id is known but the
///   object hasn't been fetched (would render a skeleton cell). Currently
///   reserved; the membership sweep skips ids without a row rather than writing
///   these.
/// - `full` — the complete object (custom fields, permissions, `user_can_change`).
///
/// File blobs and OCR content are deliberately *not* tiers here — they're
/// orthogonal axes (the on-disk `ContentStore`, a future `content` marker).
/// `Comparable` so the non-downgrade upsert keeps a `full` row when a lesser
/// (`idOnly`) write would downgrade it.
public enum DocumentProjection: Int, Codable, Sendable, Comparable {
  case idOnly = 0
  case full = 1

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  // Tolerant decode so legacy rows written before the collapse (metadata = 1,
  // detail = 2) read back as `full` instead of failing.
  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(Int.self)
    self = raw <= 0 ? .idOnly : .full
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
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
    // Carried by `full` rows (the list's `full_perms`); preserved when a lesser
    // (`idOnly`) upsert would otherwise downgrade the row.
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
    detailFetchedAt = projectionLevel == .full ? Date() : nil
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
