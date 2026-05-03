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

struct ApiTag: Codable, Sendable {
  var id: UInt
  var is_inbox_tag: Bool
  var name: String
  var slug: String
  var color: HexColor
  var match: String
  var matching_algorithm: MatchingAlgorithm
  var is_insensitive: Bool
  // Introduced by paperless-ngx v2.19.0 (tag nesting, PR #10833). Missing on
  // older backends, which decodes as nil.
  var parent: UInt?
  var children: [ApiTag]?
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
      isInsensitive: is_insensitive,
      parent: parent
    )
  }
}

extension Sequence where Element == ApiTag {
  // Flattens each element's `children` subtree (introduced in v2.19.0) and
  // deduplicates by id (first-seen wins). Pre-v2.19 backends return a flat
  // list with no `children`, so this is a no-op there. v2.19.0–2.19.2
  // returned nested tags both at the root and inside their parent's
  // `children`, so dedup is required to avoid duplicates.
  var flattenedUnique: [ApiTag] {
    func walk(_ tag: ApiTag, into result: inout [ApiTag], seen: inout Set<UInt>) {
      guard seen.insert(tag.id).inserted else { return }
      result.append(tag)
      for child in tag.children ?? [] {
        walk(child, into: &result, seen: &seen)
      }
    }

    var seen = Set<UInt>()
    var result: [ApiTag] = []
    for tag in self {
      walk(tag, into: &result, seen: &seen)
    }
    return result
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
  var parent: UInt?
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
      set_permissions: proto.permissions,
      parent: proto.parent
    )
  }
}

// MARK: - Wire type for updating tags

@Codable
struct ApiTagUpdate: Sendable {
  var id: UInt
  var is_inbox_tag: Bool
  var name: String
  var slug: String
  var color: HexColor
  var match: String
  var matching_algorithm: MatchingAlgorithm
  var is_insensitive: Bool
  // Encode as explicit JSON `null` when cleared so the paperless-ngx update
  // endpoint actually unsets the parent (it would otherwise treat a missing
  // key as "unchanged" and silently no-op).
  @CodedBy(NullCoder<UInt>())
  var parent: UInt?
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
      is_insensitive: tag.isInsensitive,
      parent: tag.parent
    )
  }
}
