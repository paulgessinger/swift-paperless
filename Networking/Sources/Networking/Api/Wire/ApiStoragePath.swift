//
//  ApiStoragePath.swift
//  Networking
//

import DataModel

// MARK: - Wire type for reading storage paths

struct ApiStoragePath: Codable, Sendable {
  var id: UInt
  var name: String
  var path: String
  var slug: String
  var matching_algorithm: MatchingAlgorithm
  var match: String
  var is_insensitive: Bool
}

extension ApiStoragePath {
  var domain: StoragePath {
    StoragePath(
      id: id,
      name: name,
      path: path,
      slug: slug,
      matchingAlgorithm: matching_algorithm,
      match: match,
      isInsensitive: is_insensitive
    )
  }
}

// MARK: - Wire type for creating storage paths

struct ApiStoragePathCreate: Encodable, Sendable {
  var name: String
  var path: String
  var matching_algorithm: MatchingAlgorithm
  var match: String
  var is_insensitive: Bool
  var owner: Owner
  var set_permissions: Permissions?
}

extension ApiStoragePathCreate {
  init(from proto: ProtoStoragePath) {
    self.init(
      name: proto.name,
      path: proto.path,
      matching_algorithm: proto.matchingAlgorithm,
      match: proto.match,
      is_insensitive: proto.isInsensitive,
      owner: proto.owner,
      set_permissions: proto.permissions
    )
  }
}

// MARK: - Wire type for updating storage paths

struct ApiStoragePathUpdate: Encodable, Sendable {
  var id: UInt
  var name: String
  var path: String
  var matching_algorithm: MatchingAlgorithm
  var match: String
  var is_insensitive: Bool
}

extension ApiStoragePathUpdate {
  init(from storagePath: StoragePath) {
    self.init(
      id: storagePath.id,
      name: storagePath.name,
      path: storagePath.path,
      matching_algorithm: storagePath.matchingAlgorithm,
      match: storagePath.match,
      is_insensitive: storagePath.isInsensitive
    )
  }
}
