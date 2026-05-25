//
//  RouteHandler.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 05.01.26.
//

import AppShared
import Common
import SwiftUI

/// Holds the route currently being processed by a scene. One instance per
/// SwiftUI scene (owned as `@State` by `MainView`) so multi-window setups
/// don't share routing state across scenes — see SceneDelegate for the
/// shortcut-item bridge that round-trips URLs back through SwiftUI's
/// scene-scoped `.onOpenURL`.
@Observable
@MainActor
class RouteManager {
  var pendingRoute: Route?
}
