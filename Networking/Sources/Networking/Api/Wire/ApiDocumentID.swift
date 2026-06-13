//
//  ApiDocumentID.swift
//  Networking
//
//  The id-only (Tier-0) projection of the documents list (`?fields=id`). A
//  dedicated lightweight wire type rather than making every `ApiDocument` field
//  optional — that would gut the full-document decode contract. Used by the
//  remote-delete reconcile to fetch the authoritative live id set cheaply.
//

import Foundation

struct ApiDocumentID: Decodable, Sendable {
  let id: UInt
}
