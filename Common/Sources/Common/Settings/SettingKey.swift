//
//  SettingKey.swift
//  Common
//
//  Created by Paul Gessinger on 26.07.26.
//

import Foundation

/// Where a setting is persisted.
///
/// The scope is a property of the key, not of the store: some settings are
/// meaningful only on the install that wrote them, while others have to be
/// visible to the ShareExtension as well.
public enum SettingScope: String, Sendable, CaseIterable {
  /// `UserDefaults.standard` — never leaves this install, and is invisible to
  /// app extensions.
  ///
  /// Correct for anything tied to the device or the install: biometric lock
  /// (the enrolled biometrics differ per device) and the stored app version
  /// (it drives the release-notes sheet, which should show up once per
  /// install).
  case device

  /// The app group suite — shared with the ShareExtension.
  case shared
}

/// The declaration of a single setting: its name on disk, its default, and
/// where it is persisted.
///
/// Keys are declared once, in one place, and read through ``SettingsStore``.
/// The default value lives on the key rather than at each call site, so
/// readers cannot disagree about what "unset" means.
public struct SettingKey<Value: Codable & Sendable>: Sendable {
  /// The key as written to `UserDefaults`. This is persisted user data:
  /// renaming it orphans the stored value.
  public let name: String

  public let defaultValue: Value

  public let scope: SettingScope

  public init(_ name: String, default defaultValue: Value, scope: SettingScope = .device) {
    self.name = name
    self.defaultValue = defaultValue
    self.scope = scope
  }
}
