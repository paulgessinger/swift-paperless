//
//  ApiDocument.swift
//  Networking
//

import Common
import DataModel
import Foundation

// MARK: - Wire type for reading documents
//
// Public because `ApiRepository.documents(filter:)` exposes
// `ApiPagedSource<ApiDocument, Document>` (Repository's `Documents`
// associated-type pin); the wire type itself surfaces in that public
// signature even though all consumers should map to `.domain` immediately.

public struct ApiDocument: Codable, Sendable {
  var id: UInt
  var title: String
  var archive_serial_number: UInt?
  var document_type: UInt?
  var correspondent: UInt?
  // `created` arrives as YYYY-MM-DD; @DateOnlyCodable parses in the local timezone
  // (matches the previous DataModel.Document behaviour) so callers don't see
  // a one-day shift when the host is east of UTC.
  @DateOnlyCodable var created: Date
  var tags: [UInt]
  var added: Date?
  var modified: Date?
  var original_file_name: String?
  var archived_file_name: String?
  var storage_path: UInt?
  var owner: Owner?
  var page_count: Int?
  // `notes` may arrive as a list of full DocumentNote objects (default in
  // recent paperless-ngx) or as a list of UInt ids on older backends; the
  // payload normalizes that to just a count.
  var notes: ApiNotesPayload?
  var custom_fields: CustomFieldRawEntryList?
  // Read-only on the wire; absent on backends predating multi-version support.
  var versions: [ApiDocumentVersion]?
  var permissions: Permissions?
}

extension ApiDocument {
  public var domain: Document {
    var doc = Document(
      id: id,
      title: title,
      asn: archive_serial_number,
      documentType: document_type,
      correspondent: correspondent,
      created: created,
      tags: tags,
      added: added,
      modified: modified,
      originalFileName: original_file_name,
      archivedFileName: archived_file_name,
      storagePath: storage_path,
      owner: owner ?? .unset,
      pageCount: page_count,
      notes: notes?.domain ?? NotesPayload(),
      customFields: custom_fields ?? CustomFieldRawEntryList(),
      versions: versions?.map(\.domain) ?? []
    )
    doc.permissions = permissions
    return doc
  }
}

// MARK: - Wire type for updating documents
//
// `@NullCodable` makes the server actually unset a foreign key when we send
// Swift `nil` (a missing key is treated as "unchanged" by paperless-ngx,
// while `null` means "clear"). `@DateOnlyCodable` keeps `created` as YYYY-MM-DD.

struct ApiDocumentUpdate: Codable, Sendable {
  var id: UInt
  var title: String

  @NullCodable var archive_serial_number: UInt?

  @NullCodable var document_type: UInt?

  @NullCodable var correspondent: UInt?

  @DateOnlyCodable var created: Date

  var tags: [UInt]

  @NullCodable var storage_path: UInt?

  var owner: Owner

  @NullCodable var page_count: Int?

  var custom_fields: CustomFieldRawEntryList
  var set_permissions: Permissions?
}

extension ApiDocumentUpdate {
  init(from document: Document) {
    self.init(
      id: document.id,
      title: document.title,
      archive_serial_number: document.asn,
      document_type: document.documentType,
      correspondent: document.correspondent,
      created: document.created,
      tags: document.tags,
      storage_path: document.storagePath,
      owner: document.owner,
      page_count: document.pageCount,
      custom_fields: document.customFields,
      set_permissions: document.permissions
    )
  }
}

// MARK: - Notes payload (decode-only)
//
// The shape of "notes" in a document response depends on the backend:
// - 2.15 and later (#9336): the list `/notes/` returns, with the user nested.
// - Earlier 2.x: the raw note rows (`depth = 1`), which also carry `document`
//   and give the user only as an id, so an author would show without a name.
// - Around #8948: note ids.
// Only the first is kept as the notes themselves; the rest give the count.

struct ApiNotesPayload: Codable, Sendable {
  let count: Int
  let notes: [ApiDocumentNote]?

  /// The key only the raw note rows carry.
  private struct RawRowMarker: Decodable {
    let document: UInt?
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let notes = try? container.decode([ApiDocumentNote].self) {
      count = notes.count
      let rawRows = try container.decode([RawRowMarker].self).contains { $0.document != nil }
      self.notes = rawRows ? nil : notes
    } else {
      count = try container.decode([UInt].self).count
      notes = nil
    }
  }

  // The full round-trip is never exercised — the only writer is
  // ApiDocumentUpdate, which doesn't carry notes.
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode([UInt]())
  }
}

extension ApiNotesPayload {
  var domain: NotesPayload {
    guard let notes else { return NotesPayload(count: count) }
    return NotesPayload(notes: notes.map(\.domain))
  }
}
