//
//  ApiTag.swift
//  Networking
//
//  Created by Paul Gessinger on 02.04.26.
//

import Common
import DataModel
import MetaCodable

// MARK: - Wire type for reading tags from the API

@Codable
@CodingKeys(.snake_case)
struct ApiTag: Sendable {
  var id: UInt
  var isInboxTag: Bool
  var name: String
  var slug: String
  var color: HexColor
  var match: String
  var matchingAlgorithm: MatchingAlgorithm
  var isInsensitive: Bool
}

extension ApiTag {
  var domain: Tag {
    Tag(
      id: id,
      isInboxTag: isInboxTag,
      name: name,
      slug: slug,
      color: color,
      match: match,
      matchingAlgorithm: matchingAlgorithm,
      isInsensitive: isInsensitive
    )
  }
}

// MARK: - Wire type for creating tags

@Codable
@CodingKeys(.snake_case)
struct ApiTagCreate: Sendable {
  var isInboxTag: Bool
  var name: String
  var slug: String
  var color: HexColor
  var match: String
  var matchingAlgorithm: MatchingAlgorithm
  var isInsensitive: Bool
  var owner: Owner
  var setPermissions: Permissions?
}

extension ApiTagCreate {
  init(from proto: ProtoTag) {
    self.init(
      isInboxTag: proto.isInboxTag,
      name: proto.name,
      slug: proto.slug,
      color: proto.color,
      match: proto.match,
      matchingAlgorithm: proto.matchingAlgorithm,
      isInsensitive: proto.isInsensitive,
      owner: proto.owner,
      setPermissions: proto.permissions
    )
  }
}

// MARK: - Wire type for updating tags

@Codable
@CodingKeys(.snake_case)
struct ApiTagUpdate: Sendable {
  var id: UInt
  var isInboxTag: Bool
  var name: String
  var slug: String
  var color: HexColor
  var match: String
  var matchingAlgorithm: MatchingAlgorithm
  var isInsensitive: Bool
}

extension ApiTagUpdate {
  init(from tag: Tag) {
    self.init(
      id: tag.id,
      isInboxTag: tag.isInboxTag,
      name: tag.name,
      slug: tag.slug,
      color: tag.color,
      match: tag.match,
      matchingAlgorithm: tag.matchingAlgorithm,
      isInsensitive: tag.isInsensitive
    )
  }
}
