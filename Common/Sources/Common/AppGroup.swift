//
//  AppGroup.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.05.26.
//

import Foundation

/// The single source of truth for the shared app-group identifier used by the
/// main app, the Share Extension, and any future extensions (e.g. File
/// Provider) to reach shared containers and `UserDefaults`.
///
/// The `.entitlements` files must repeat this literal — Xcode reads them before
/// any Swift runs — but every Swift call site should reference this constant
/// rather than hard-coding the string.
public enum AppGroup {
  public static let identifier = "group.com.paulgessinger.swift-paperless"
}
