//
//  ApiSuggestions.swift
//  Networking
//

import DataModel
import Foundation

struct ApiSuggestions: Decodable, Sendable {
  var correspondents: [UInt]?
  var tags: [UInt]?
  var document_types: [UInt]?
  var storage_paths: [UInt]?
  var dates: [Date]?
}

extension ApiSuggestions {
  var domain: Suggestions {
    Suggestions(
      correspondents: correspondents ?? [],
      tags: tags ?? [],
      documentTypes: document_types ?? [],
      storagePaths: storage_paths ?? [],
      dates: dates ?? []
    )
  }
}
