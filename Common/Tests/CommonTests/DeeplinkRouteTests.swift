//
//  DeeplinkRouteTests.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 04.01.26.
//

import Foundation
import Testing

@testable import Common

@Suite
struct DeeplinkRouteTests {

  @Test func testV1Parsing() async throws {
    let server = try #require(URL(string: "https://user@example.com:1234")?.stringDroppingScheme)

    let base = try #require(URL(string: "x-paperless://v1")).appending(component: server)

    print(base)

    // Test valid document route
    let documentRoute = Route(from: base.appendingPathComponent("document/123"))
    #expect(documentRoute != nil)
    #expect(documentRoute?.action == .document(id: 123))
    #expect(documentRoute?.server == server)

    // Test valid scan action route
    let scanRoute = Route(from: base.appendingPathComponent("action/scan"))
    #expect(scanRoute != nil)
    #expect(scanRoute?.action == .scan)
    #expect(scanRoute?.server == server)

    // Test invalid routes
    #expect(Route(from: base.appendingPathComponent("documents/123")) == nil)  // Wrong resource name
    #expect(Route(from: base.appendingPathComponent("document")) == nil)  // Missing ID
    #expect(Route(from: base.appendingPathComponent("document/abc")) == nil)  // Invalid ID
    #expect(Route(from: base.appendingPathComponent("action")) == nil)  // Missing subaction
    #expect(Route(from: base.appendingPathComponent("action/invalid")) == nil)  // Invalid subaction
    #expect(Route(from: base.appendingPathComponent("invalid/123")) == nil)  // Invalid resource
  }

  @Test func testV2ParsingFails() throws {
    let server = try #require(URL(string: "https://example.com")?.stringDroppingScheme)

    let v2Base = try #require(URL(string: "x-paperless://v2")).appending(component: server)

    // All v2 URLs should fail to parse since Route only supports v1
    #expect(Route(from: v2Base.appendingPathComponent("document/123")) == nil)
    #expect(Route(from: v2Base.appendingPathComponent("action/scan")) == nil)
  }

}
