//
//  ApiTag.swift
//  Networking
//
//  Created by Paul Gessinger on 02.04.26.
//

import Common
import DataModel

// MARK: - Wire type for reading tags from the API

struct ApiTag: Codable, Sendable {
  var id: UInt
  var is_inbox_tag: Bool
  var name: String
  var slug: String
  var color: HexColor
  var match: String
  var matching_algorithm: MatchingAlgorithm
  var is_insensitive: Bool
}

extension ApiTag {
  var domain: Tag {
    Tag(
      id: id,
      isInboxTag: is_inbox_tag,
      name: name,
      slug: slug,
      color: color,
      match: match,
      matchingAlgorithm: matching_algorithm,
      isInsensitive: is_insensitive
    )
  }
}

// MARK: - Wire type for creating tags

struct ApiTagCreate: Encodable, Sendable {
  var is_inbox_tag: Bool
  var name: String
  var slug: String
  var color: HexColor
  var match: String
  var matching_algorithm: MatchingAlgorithm
  var is_insensitive: Bool
  var owner: Owner
  var set_permissions: Permissions?
}

extension ApiTagCreate {
  init(from proto: ProtoTag) {
    self.init(
      is_inbox_tag: proto.isInboxTag,
      name: proto.name,
      slug: proto.slug,
      color: proto.color,
      match: proto.match,
      matching_algorithm: proto.matchingAlgorithm,
      is_insensitive: proto.isInsensitive,
      owner: proto.owner,
      set_permissions: proto.permissions
    )
  }
}

// MARK: - Wire type for updating tags

struct ApiTagUpdate: Encodable, Sendable {
  var id: UInt
  var is_inbox_tag: Bool
  var name: String
  var slug: String
  var color: HexColor
  var match: String
  var matching_algorithm: MatchingAlgorithm
  var is_insensitive: Bool
}

extension ApiTagUpdate {
  init(from tag: Tag) {
    self.init(
      id: tag.id,
      is_inbox_tag: tag.isInboxTag,
      name: tag.name,
      slug: tag.slug,
      color: tag.color,
      match: tag.match,
      matching_algorithm: tag.matchingAlgorithm,
      is_insensitive: tag.isInsensitive
    )
  }
}
