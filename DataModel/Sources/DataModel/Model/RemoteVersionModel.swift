//
//  RemoteVersionModel.swift
//  DataModel
//
//  Created by Paul Gessinger on 24.01.26.
//

import Common

public struct RemoteVersion: Sendable {
  public let version: Version?
  public let updateAvailable: Bool

  public init(version: Version?, updateAvailable: Bool) {
    self.version = version
    self.updateAvailable = updateAvailable
  }
}
