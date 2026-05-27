//
//  ApiCorrespondent.swift
//  Networking
//

import DataModel
import Foundation

// MARK: - Wire type for reading correspondents from the API

struct ApiCorrespondent: Decodable, Sendable {
  var id: UInt
  var document_count: UInt?
  var last_correspondence: Date?
  var name: String
  var slug: String
  var matching_algorithm: MatchingAlgorithm
  var match: String
  var is_insensitive: Bool
}

extension ApiCorrespondent {
  var domain: Correspondent {
    Correspondent(
      id: id,
      documentCount: document_count,
      lastCorrespondence: last_correspondence,
      name: name,
      slug: slug,
      matchingAlgorithm: matching_algorithm,
      match: match,
      isInsensitive: is_insensitive
    )
  }
}

// MARK: - Wire type for creating correspondents

struct ApiCorrespondentCreate: Encodable, Sendable {
  var name: String
  var matching_algorithm: MatchingAlgorithm
  var match: String
  var is_insensitive: Bool
  var owner: Owner
  var set_permissions: Permissions?
}

extension ApiCorrespondentCreate {
  init(from proto: ProtoCorrespondent) {
    self.init(
      name: proto.name,
      matching_algorithm: proto.matchingAlgorithm,
      match: proto.match,
      is_insensitive: proto.isInsensitive,
      owner: proto.owner,
      set_permissions: proto.permissions
    )
  }
}

// MARK: - Wire type for updating correspondents

struct ApiCorrespondentUpdate: Encodable, Sendable {
  var id: UInt
  var name: String
  var matching_algorithm: MatchingAlgorithm
  var match: String
  var is_insensitive: Bool
}

extension ApiCorrespondentUpdate {
  init(from correspondent: Correspondent) {
    self.init(
      id: correspondent.id,
      name: correspondent.name,
      matching_algorithm: correspondent.matchingAlgorithm,
      match: correspondent.match,
      is_insensitive: correspondent.isInsensitive
    )
  }
}
