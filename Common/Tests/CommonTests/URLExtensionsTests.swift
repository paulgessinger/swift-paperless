//
//  URLExtensionsTests.swift
//  CommonTests
//
//  Created by Paul Gessinger on 04.01.26.
//

import Foundation
import Testing

@testable import Common

struct URLExtensionsTests {

  @Test func testStringDroppingScheme() throws {
    // Test with https scheme
    let httpsURL = try #require(URL(string: "https://user@example.com:1234"))
    #expect(httpsURL.stringDroppingScheme == "user@example.com:1234")

    // Test with custom scheme
    let customURL = try #require(URL(string: "x-paperless://v1/path"))
    #expect(customURL.stringDroppingScheme == "v1/path")

    // Test with http scheme
    let httpURL = try #require(URL(string: "http://example.com/path"))
    #expect(httpURL.stringDroppingScheme == "example.com/path")

    // Test URL without scheme (relative URL)
    let relativeURL = try #require(
      URL(string: "example.com/path", relativeTo: URL(string: "http://base.com")))
    #expect(relativeURL.stringDroppingScheme != nil)
  }
}
