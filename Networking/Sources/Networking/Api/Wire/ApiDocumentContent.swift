//
//  ApiDocumentContent.swift
//  Networking
//
//  A document's full text with what it is filed under, from the documents
//  list projected to those fields (`Endpoint.documentContents(ids:)`).
//

import Foundation

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
