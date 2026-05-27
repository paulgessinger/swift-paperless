//
//  ApiDocument.swift
//  Networking
//

import Common
import DataModel
import Foundation
import MetaCodable

// MARK: - Wire type for reading documents
//
// Public because `ApiRepository.documents(filter:)` exposes
// `ApiPagedSource<ApiDocument, Document>` (Repository's `Documents`
// associated-type pin); the wire type itself surfaces in that public
// signature even though all consumers should map to `.domain` immediately.

@Codable
public struct ApiDocument: Sendable {
  var id: UInt
  var title: String
  var archive_serial_number: UInt?
  var document_type: UInt?
  var correspondent: UInt?
  // `created` arrives as YYYY-MM-DD; DateOnlyCoder parses in the local
  // timezone (matches the previous DataModel.Document behaviour) so callers
  // don't see a one-day shift when the host is east of UTC.
  @CodedBy(DateOnlyCoder())
  var created: Date
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
  var user_can_change: Bool?
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
      userCanChange: user_can_change ?? true
    )
    doc.permissions = permissions
    return doc
  }
}

// MARK: - Wire type for updating documents
//
// MetaCodable here earns its keep: `@CodedBy(NullCoder<…>)` is what makes the
// server actually unset a foreign key when we send Swift `nil` (a missing
// key is treated as "unchanged" by paperless-ngx), and `@CodedBy(DateOnlyCoder())`
// keeps `created` as YYYY-MM-DD on the wire.

@Codable
struct ApiDocumentUpdate: Sendable {
  var id: UInt
  var title: String

  @CodedBy(NullCoder<UInt>())
  var archive_serial_number: UInt?

  @CodedBy(NullCoder<UInt>())
  var document_type: UInt?

  @CodedBy(NullCoder<UInt>())
  var correspondent: UInt?

  @CodedBy(DateOnlyCoder())
  var created: Date

  var tags: [UInt]

  @CodedBy(NullCoder<UInt>())
  var storage_path: UInt?

  var owner: Owner

  @CodedBy(NullCoder<Int>())
  var page_count: Int?

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
// The /api/documents/<id>/ payload returns "notes" as either a list of full
// note objects or a list of note ids depending on backend version. We only
// care about the count for the document model.

struct ApiNotesPayload: Codable, Sendable {
  let count: Int

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let notes = try? container.decode([ApiDocumentNote].self) {
      count = notes.count
    } else {
      count = try container.decode([UInt].self).count
    }
  }

  // Required to satisfy ApiDocument's @Codable synthesis. The full
  // round-trip is never exercised — the only writer is ApiDocumentUpdate,
  // which doesn't carry notes.
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode([UInt]())
  }
}

extension ApiNotesPayload {
  var domain: NotesPayload {
    var p = NotesPayload()
    p.count = count
    return p
  }
}
