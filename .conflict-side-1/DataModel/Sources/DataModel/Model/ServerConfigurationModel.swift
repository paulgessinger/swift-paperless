//
//  ServerConfigurationModel.swift
//  DataModel
//
//  Created by Claude on 09.07.25.
//

import Foundation
import MetaCodable

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct ServerConfiguration: Sendable, Identifiable {
  public var id: UInt
  public var barcodeAsnPrefix: String?
}
