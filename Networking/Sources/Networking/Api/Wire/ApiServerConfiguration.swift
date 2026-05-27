//
//  ApiServerConfiguration.swift
//  Networking
//

import DataModel

struct ApiServerConfiguration: Decodable, Sendable, Identifiable {
  var id: UInt
  var barcode_asn_prefix: String?
}

extension ApiServerConfiguration {
  var domain: ServerConfiguration {
    ServerConfiguration(id: id, barcodeAsnPrefix: barcode_asn_prefix)
  }
}
