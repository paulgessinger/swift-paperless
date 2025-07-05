//
//  URLMacroTest.swift
//  Common
//
//  Created by Paul Gessinger on 31.12.24.
//

import Foundation
import MacroTesting
import SwiftSyntax
import XCTest

@testable import Common
@testable import CommonMacros

final class URLMacroTest: XCTestCase {
  override func invokeTest() {
    withMacroTesting(
      record: false,
      macros: ["URL": URLMacro.self]
    ) {
      super.invokeTest()
    }
  }

  func testValidExpansion() throws {
    assertMacro {
      """
      #URL("https://example.com")
      """
    } expansion: {
      """
      URL(string: "https://example.com")!
      """
    }
  }

  func testInvalidURL() throws {
    assertMacro {
      """
      #URL("https://example<>.com")
      """
    } diagnostics: {
      """
      #URL("https://example<>.com")
      ┬────────────────────────────
      ╰─ 🛑 Malformed URL: "https://example<>.com"
      """
    }
  }

  func testNoLiteral() throws {
    assertMacro {
      """
      #URL(17)
      """
    } diagnostics: {
      """
      #URL(17)
      ┬───────
      ╰─ 🛑 Not a static string literal
      """
    }

    assertMacro {
      """
      let url = "https://example.com"
      #URL(url)
      """
    } diagnostics: {
      """
      let url = "https://example.com"
      #URL(url)
      ┬────────
      ╰─ 🛑 Not a static string literal
      """
    }
  }

  func testEmptyArgument() throws {
    assertMacro {
      """
      #URL("")
      """
    } diagnostics: {
      """
      #URL("")
      ┬───────
      ╰─ 🛑 Malformed URL: ""
      """
    }
  }

  func testNoArgument() throws {
    assertMacro {
      """
      #URL()
      """
    } diagnostics: {
      """
      #URL()
      ┬─────
      ╰─ 🛑 Not a static string literal
      """
    }
  }
}
