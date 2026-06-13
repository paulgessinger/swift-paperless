//
//  ApiDocumentVersion.swift
//  Networking
//

import DataModel
import Foundation

// MARK: - Wire type for the per-document `versions` array
//
// Matches paperless-ngx OpenAPI `DocumentVersionInfo`. `version_label` and
// `checksum` are nullable; the rest are required. Read-only — there is no
// corresponding Update variant because new versions are created via the
// (out-of-scope) `POST /documents/{id}/update_version/` multipart endpoint,
// not by writing this struct back.

struct ApiDocumentVersion: Codable, Sendable {
  var id: UInt
  var added: Date
  var version_label: String?
  var checksum: String?
  var is_root: Bool
}

extension ApiDocumentVersion {
  var domain: DocumentVersion {
    DocumentVersion(
      id: id, added: added, label: version_label,
      checksum: checksum, isRoot: is_root)
  }
}
