import DataModel
import Foundation
import GRDB

/// GRDB record for a document's cached notes list (`document_note` table, keyed
/// `(server_id, document_id)`).
///
/// The whole list lives in one row's JSON `data` blob: the `/notes/` endpoint
/// always returns the full list, and create/delete return the updated full list,
/// so a cache write is a row *replace*, never a per-note merge. `DocumentNote`
/// isn't `Codable`, so the long tail is an explicit storage `NotePayload` mapped
/// by hand (the Stage 3 principle: storage shape ≠ wire shape ≠ domain shape).
public struct DocumentNoteRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "document_note"

  public var serverId: UUID
  public var documentId: UInt
  public var notes: [NotePayload]

  /// Storage-local copy of a `DocumentNote` (`DocumentNote.User` is already a
  /// wire-symmetric `Codable` leaf, so it's reused directly).
  public struct NotePayload: Codable, Sendable, Equatable {
    public var id: UInt
    public var note: String
    public var created: Date
    public var user: DocumentNote.User?
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case documentId = "document_id"
    case notes = "data"
  }

  public static func databaseJSONEncoder(for column: String) -> JSONEncoder {
    ElementStorage.encoder
  }

  public static func databaseJSONDecoder(for column: String) -> JSONDecoder {
    ElementStorage.decoder
  }
}

extension DocumentNoteRecord {
  public init(serverId: UUID, documentId: UInt, notes: [DocumentNote]) {
    self.serverId = serverId
    self.documentId = documentId
    self.notes = notes.map {
      NotePayload(id: $0.id, note: $0.note, created: $0.created, user: $0.user)
    }
  }

  public var domain: [DocumentNote] {
    notes.map {
      DocumentNote(id: $0.id, note: $0.note, created: $0.created, user: $0.user)
    }
  }
}
