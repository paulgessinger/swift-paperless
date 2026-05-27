//
//  ApiDocumentNote.swift
//  Networking
//

import DataModel
import Foundation

// MARK: - Wire type for document notes
//
// The /notes/ endpoint returns `user` as one of: a full user object, just an
// id, or null — all in the same field across backend versions. The custom
// decoder folds the variants down to `DocumentNote.User?`.

struct ApiDocumentNote: Decodable, Sendable {
  var id: UInt
  var note: String
  var created: Date
  var user: DocumentNote.User?

  enum CodingKeys: String, CodingKey {
    case id, note, created, user
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UInt.self, forKey: .id)
    note = try container.decode(String.self, forKey: .note)
    created = try container.decode(Date.self, forKey: .created)

    if container.contains(.user) {
      if try container.decodeNil(forKey: .user) {
        user = nil
      } else if let userStruct = try? container.decode(DocumentNote.User.self, forKey: .user) {
        user = userStruct
      } else if let userId = try? container.decode(UInt.self, forKey: .user) {
        user = DocumentNote.User(id: userId, username: "")
      } else {
        user = nil
      }
    } else {
      user = nil
    }
  }
}

extension ApiDocumentNote {
  var domain: DocumentNote {
    DocumentNote(id: id, note: note, created: created, user: user)
  }
}

// MARK: - Wire type for creating a document note (POST body)

struct ApiDocumentNoteCreate: Encodable, Sendable {
  var note: String

  init(from proto: ProtoDocument.Note) {
    note = proto.note
  }
}
