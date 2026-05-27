//
//  ApiServerConfiguration.swift
//  Networking
//

import DataModel
import MetaCodable

@Codable
@CodingKeys(.snake_case)
struct ApiServerConfiguration: Sendable, Identifiable {
  var id: UInt
  var barcodeAsnPrefix: String?
}

extension ApiServerConfiguration {
  var domain: ServerConfiguration {
    ServerConfiguration(id: id, barcodeAsnPrefix: barcodeAsnPrefix)
  }
}
