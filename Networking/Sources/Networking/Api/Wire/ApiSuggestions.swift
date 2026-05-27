//
//  ApiSuggestions.swift
//  Networking
//

import DataModel
import Foundation
import MetaCodable

@Codable
@CodingKeys(.snake_case)
struct ApiSuggestions: Sendable {
  @Default([UInt]())
  var correspondents: [UInt]

  @Default([UInt]())
  var tags: [UInt]

  @Default([UInt]())
  var documentTypes: [UInt]

  @Default([UInt]())
  var storagePaths: [UInt]

  @Default([Date]())
  var dates: [Date]
}

extension ApiSuggestions {
  var domain: Suggestions {
    Suggestions(
      correspondents: correspondents,
      tags: tags,
      documentTypes: documentTypes,
      storagePaths: storagePaths,
      dates: dates
    )
  }
}
