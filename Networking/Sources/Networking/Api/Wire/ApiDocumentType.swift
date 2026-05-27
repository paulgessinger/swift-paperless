//
//  ApiDocumentType.swift
//  Networking
//

import DataModel
import MetaCodable

// MARK: - Wire type for reading document types

@Codable
@CodingKeys(.snake_case)
struct ApiDocumentType: Sendable {
  var id: UInt
  var name: String
  var slug: String
  var match: String
  var matchingAlgorithm: MatchingAlgorithm
  var isInsensitive: Bool
}

extension ApiDocumentType {
  var domain: DocumentType {
    DocumentType(
      id: id,
      name: name,
      slug: slug,
      match: match,
      matchingAlgorithm: matchingAlgorithm,
      isInsensitive: isInsensitive
    )
  }
}

// MARK: - Wire type for creating document types

struct ApiDocumentTypeCreate: Encodable, Sendable {
  var name: String
  var match: String
  var matching_algorithm: MatchingAlgorithm
  var is_insensitive: Bool
  var owner: Owner
  var set_permissions: Permissions?
}

extension ApiDocumentTypeCreate {
  init(from proto: ProtoDocumentType) {
    self.init(
      name: proto.name,
      match: proto.match,
      matching_algorithm: proto.matchingAlgorithm,
      is_insensitive: proto.isInsensitive,
      owner: proto.owner,
      set_permissions: proto.permissions
    )
  }
}

// MARK: - Wire type for updating document types

struct ApiDocumentTypeUpdate: Encodable, Sendable {
  var id: UInt
  var name: String
  var match: String
  var matching_algorithm: MatchingAlgorithm
  var is_insensitive: Bool
}

extension ApiDocumentTypeUpdate {
  init(from documentType: DocumentType) {
    self.init(
      id: documentType.id,
      name: documentType.name,
      match: documentType.match,
      matching_algorithm: documentType.matchingAlgorithm,
      is_insensitive: documentType.isInsensitive
    )
  }
}
