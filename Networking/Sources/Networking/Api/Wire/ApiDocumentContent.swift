//
//  ApiDocumentContent.swift
//  Networking
//
//  A document's full text with what it is filed under, from the documents
//  list projected to those fields (`Endpoint.documentContents(ids:)`).
//

import Foundation

/// Not `ApiDocument`, which requires `title`, `created` and `tags`: the
/// request leaves out the metadata, since a batch of texts already runs to
/// megabytes.
struct ApiDocumentContent: Decodable, Sendable {
  var id: UInt
  var modified: Date?
  var versions: [ApiDocumentVersion]?
  var content: String?

  /// The version the text is filed under, as `Document.currentVersionID`.
  var currentVersionID: UInt {
    versions?.map(\.id).max() ?? id
  }
}
