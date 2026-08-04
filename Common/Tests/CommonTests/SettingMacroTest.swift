//
//  SettingMacroTest.swift
//  Common
//
//  Created by Paul Gessinger on 26.07.26.
//

import Foundation
import MacroTesting
import SwiftSyntax
import XCTest

@testable import Common
@testable import CommonMacros

final class SettingMacroTest: XCTestCase {
  override func invokeTest() {
    withMacroTesting(
      record: false,
      macros: ["Setting": SettingMacro.self]
    ) {
      super.invokeTest()
    }
  }

  func testExpansion() throws {
    assertMacro {
      """
      final class Settings {
        @Setting(.documentDeleteConfirmation)
        var documentDeleteConfirmation: Bool
      }
      """
    } expansion: {
      #"""
      final class Settings {
        var documentDeleteConfirmation: Bool {
          get {
            access(keyPath: \.documentDeleteConfirmation)
            return store[.documentDeleteConfirmation]
          }
          set {
            withMutation(keyPath: \.documentDeleteConfirmation) {
              store[.documentDeleteConfirmation] = newValue
            }
          }
        }
      }
      """#
    }
  }

  func testOptionalValue() throws {
    assertMacro {
      """
      final class Settings {
        @Setting(.currentAppVersion)
        var currentAppVersion: AppVersion?
      }
      """
    } expansion: {
      #"""
      final class Settings {
        var currentAppVersion: AppVersion? {
          get {
            access(keyPath: \.currentAppVersion)
            return store[.currentAppVersion]
          }
          set {
            withMutation(keyPath: \.currentAppVersion) {
              store[.currentAppVersion] = newValue
            }
          }
        }
      }
      """#
    }
  }

  func testNoKey() throws {
    assertMacro {
      """
      final class Settings {
        @Setting
        var documentDeleteConfirmation: Bool
      }
      """
    } diagnostics: {
      """
      final class Settings {
        @Setting
        ┬───────
        ╰─ 🛑 @Setting needs the SettingKey to read and write, e.g. @Setting(.documentDeleteConfirmation)
        var documentDeleteConfirmation: Bool
      }
      """
    }
  }
}
