//
//  ApiShareLink.swift
//  Networking
//

import DataModel
import Foundation

// MARK: - Wire type for reading share links

struct ApiShareLink: Codable, Sendable {
  var id: UInt
  var created: Date
  var expiration: Date?
  var slug: String
  var document: UInt
  var file_version: ShareLink.FileVersion
}

extension ApiShareLink {
  var domain: ShareLink {
    ShareLink(
      id: id,
      created: created,
      expiration: expiration,
      slug: slug,
      document: document,
      fileVersion: file_version
    )
  }
}

// MARK: - Wire type for creating share links

struct ApiShareLinkCreate: Encodable, Sendable {
  var document: UInt
  var expiration: Date?
  var file_version: ShareLink.FileVersion
}

extension ApiShareLinkCreate {
  init(from proto: ProtoShareLink) {
    self.init(
      document: proto.document,
      expiration: proto.expiration,
      file_version: proto.fileVersion
    )
  }
}
