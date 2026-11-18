//
//  ApiDocumentChat.swift
//  Networking
//

import Foundation

// MARK: - Wire types for the /api/documents/chat/ endpoint

/// Request body of `POST /api/documents/chat/`. Without `document_id` the
/// question goes to every document the user can see.
struct ApiDocumentChatRequest: Encodable, Sendable {
  var q: String
  var document_id: UInt?
}
