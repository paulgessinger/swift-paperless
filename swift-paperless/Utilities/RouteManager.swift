//
//  RouteHandler.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 05.01.26.
//

import Common
import SwiftUI

@Observable
@MainActor
class RouteManager {
  static let shared = RouteManager()

  private init() {}

  var pendingURL: URL?
  var pendingRoute: Route?
}
