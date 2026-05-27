//
//  ServerConfigurationModel.swift
//  DataModel
//
//  Created by Claude on 09.07.25.
//

public struct ServerConfiguration: Sendable, Identifiable {
  public var id: UInt
  public var barcodeAsnPrefix: String?

  public init(id: UInt, barcodeAsnPrefix: String? = nil) {
    self.id = id
    self.barcodeAsnPrefix = barcodeAsnPrefix
  }
}
