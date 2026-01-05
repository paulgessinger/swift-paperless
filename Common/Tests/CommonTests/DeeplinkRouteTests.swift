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

  @Test func testV1ParsingWithServer() throws {
    let serverURL = try #require(URL(string: "https://user@example.com:1234"))
    let server = try #require(serverURL.stringDroppingScheme)
    let encodedServer = server.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

    // Test valid document route with server query parameter
    let documentURL = try #require(
      URL(string: "x-paperless://v1/document/123?server=\(encodedServer)"))
    let documentRoute = Route(from: documentURL)
    #expect(documentRoute != nil)
    #expect(documentRoute?.action == .document(id: 123))
    #expect(documentRoute?.server == server)

    // Test valid scan action route with server query parameter
    let scanURL = try #require(
      URL(string: "x-paperless://v1/action/scan?server=\(encodedServer)"))
    let scanRoute = Route(from: scanURL)
    #expect(scanRoute != nil)
    #expect(scanRoute?.action == .scan)
    #expect(scanRoute?.server == server)
  }

  @Test func testV1ParsingWithoutServer() throws {
    // Test valid document route without server
    let documentURL = try #require(URL(string: "x-paperless://v1/document/456"))
    let documentRoute = Route(from: documentURL)
    #expect(documentRoute != nil)
    #expect(documentRoute?.action == .document(id: 456))
    #expect(documentRoute?.server == nil)

    // Test valid scan action route without server
    let scanURL = try #require(URL(string: "x-paperless://v1/action/scan"))
    let scanRoute = Route(from: scanURL)
    #expect(scanRoute != nil)
    #expect(scanRoute?.action == .scan)
    #expect(scanRoute?.server == nil)
  }

  @Test func testV1ParsingInvalidRoutes() throws {
    // Test invalid routes
    #expect(Route(from: URL(string: "x-paperless://v1/documents/123")!) == nil)  // Wrong resource name
    #expect(Route(from: URL(string: "x-paperless://v1/document")!) == nil)  // Missing ID
    #expect(Route(from: URL(string: "x-paperless://v1/document/abc")!) == nil)  // Invalid ID
    #expect(Route(from: URL(string: "x-paperless://v1/action")!) == nil)  // Missing subaction
    #expect(Route(from: URL(string: "x-paperless://v1/action/invalid")!) == nil)  // Invalid subaction
    #expect(Route(from: URL(string: "x-paperless://v1/invalid/123")!) == nil)  // Invalid resource
  }

  @Test func testV2ParsingFails() throws {
    // All v2 URLs should fail to parse since Route only supports v1
    #expect(Route(from: URL(string: "x-paperless://v2/document/123")!) == nil)
    #expect(Route(from: URL(string: "x-paperless://v2/action/scan")!) == nil)
  }

}
