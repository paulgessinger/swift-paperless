//
//  DeeplinkRouteTests.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 04.01.26.
//

import Common
import DataModel
import Foundation
import Testing

@Suite
struct DeeplinkRouteTests {

  @Test func testV1ParsingWithServer() throws {
    let serverURL = try #require(URL(string: "https://user@example.com:1234"))
    let server = try #require(serverURL.stringDroppingScheme)
    let encodedServer = server.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

    // Test valid document route with server query parameter
    let documentURL = try #require(
      URL(string: "x-paperless://v1/document/123?server=\(encodedServer)"))
    let documentRoute = try Route(from: documentURL)
    #expect(documentRoute.action == .document(id: 123))
    #expect(documentRoute.server == server)

    // Test valid scan action route with server query parameter
    let scanURL = try #require(
      URL(string: "x-paperless://v1/action/scan?server=\(encodedServer)"))
    let scanRoute = try Route(from: scanURL)
    #expect(scanRoute.action == .scan)
    #expect(scanRoute.server == server)
  }

  @Test func testV1ParsingWithoutServer() throws {
    // Test valid document route without server
    let documentURL = try #require(URL(string: "x-paperless://v1/document/456"))
    let documentRoute = try Route(from: documentURL)
    #expect(documentRoute.action == .document(id: 456))
    #expect(documentRoute.server == nil)

    // Test valid scan action route without server
    let scanURL = try #require(URL(string: "x-paperless://v1/action/scan"))
    let scanRoute = try Route(from: scanURL)
    #expect(scanRoute.action == .scan)
    #expect(scanRoute.server == nil)
  }

  @Test func testV1ParsingInvalidRoutes() throws {
    // Test invalid routes - should throw specific errors
    #expect(throws: Route.ParseError.unknownResource("documents")) {
      try Route(from: URL(string: "x-paperless://v1/documents/123")!)  // Wrong resource name
    }
    #expect(throws: Route.ParseError.missingDocumentId) {
      try Route(from: URL(string: "x-paperless://v1/document")!)  // Missing ID
    }
    #expect(throws: Route.ParseError.invalidDocumentId("abc")) {
      try Route(from: URL(string: "x-paperless://v1/document/abc")!)  // Invalid ID
    }
    #expect(throws: Route.ParseError.missingAction) {
      try Route(from: URL(string: "x-paperless://v1/action")!)  // Missing subaction
    }
    #expect(throws: Route.ParseError.unknownAction("invalid")) {
      try Route(from: URL(string: "x-paperless://v1/action/invalid")!)  // Invalid subaction
    }
    #expect(throws: Route.ParseError.unknownResource("invalid")) {
      try Route(from: URL(string: "x-paperless://v1/invalid/123")!)  // Invalid resource
    }
  }

  @Test func testV1SetFilterAction() throws {
    // Test set_filter with multiple tags (anyOf mode, default)
    let filterURL = try #require(URL(string: "x-paperless://v1/action/set_filter?tags=1,2,3"))
    let filterRoute = try Route(from: filterURL)
    #expect(filterRoute.action == .setFilter(tags: .anyOf(ids: [1, 2, 3])))
    #expect(filterRoute.server == nil)

    // Test set_filter with single tag
    let singleTagURL = try #require(URL(string: "x-paperless://v1/action/set_filter?tags=42"))
    let singleTagRoute = try Route(from: singleTagURL)
    #expect(singleTagRoute.action == .setFilter(tags: .anyOf(ids: [42])))

    // Test set_filter with no tags parameter (nil means don't change current filter)
    let noTagsURL = try #require(URL(string: "x-paperless://v1/action/set_filter"))
    let noTagsRoute = try Route(from: noTagsURL)
    #expect(noTagsRoute.action == .setFilter(tags: nil))

    // Test set_filter with empty tags parameter (nil means don't change current filter)
    let emptyTagsURL = try #require(URL(string: "x-paperless://v1/action/set_filter?tags="))
    let emptyTagsRoute = try Route(from: emptyTagsURL)
    #expect(emptyTagsRoute.action == .setFilter(tags: nil))

    // Test set_filter with tags=none (notAssigned)
    let noneTagsURL = try #require(URL(string: "x-paperless://v1/action/set_filter?tags=none"))
    let noneTagsRoute = try Route(from: noneTagsURL)
    #expect(noneTagsRoute.action == .setFilter(tags: .notAssigned))

    // Test set_filter with tags=any (reset to .any)
    let anyTagsURL = try #require(URL(string: "x-paperless://v1/action/set_filter?tags=any"))
    let anyTagsRoute = try Route(from: anyTagsURL)
    #expect(anyTagsRoute.action == .setFilter(tags: .any))

    // Test set_filter with server only (tags nil, won't change filter)
    let serverURL = try #require(URL(string: "https://example.com"))
    let server = try #require(serverURL.stringDroppingScheme)
    let encodedServer = server.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

    let serverOnlyURL = try #require(
      URL(string: "x-paperless://v1/action/set_filter?server=\(encodedServer)"))
    let serverOnlyRoute = try Route(from: serverOnlyURL)
    #expect(serverOnlyRoute.action == .setFilter(tags: nil))
    #expect(serverOnlyRoute.server == server)

    // Test set_filter with server and tags
    let filterWithServerURL = try #require(
      URL(string: "x-paperless://v1/action/set_filter?server=\(encodedServer)&tags=10,20"))
    let filterWithServerRoute = try Route(from: filterWithServerURL)
    #expect(filterWithServerRoute.action == .setFilter(tags: .anyOf(ids: [10, 20])))
    #expect(filterWithServerRoute.server == server)

    // Test set_filter with tag_mode=all (allOf mode with include only)
    let allOfURL = try #require(
      URL(string: "x-paperless://v1/action/set_filter?tags=1,2,3&tag_mode=all"))
    let allOfRoute = try Route(from: allOfURL)
    #expect(allOfRoute.action == .setFilter(tags: .allOf(include: [1, 2, 3], exclude: [])))

    // Test set_filter with tag_mode=all and excluded tags (!)
    let allOfExcludeURL = try #require(
      URL(string: "x-paperless://v1/action/set_filter?tags=1,2,!3,!4&tag_mode=all"))
    let allOfExcludeRoute = try Route(from: allOfExcludeURL)
    #expect(
      allOfExcludeRoute.action == .setFilter(tags: .allOf(include: [1, 2], exclude: [3, 4])))

    // Test set_filter with tag_mode=any and excluded tags should throw error
    let anyOfExcludeURL = try #require(
      URL(string: "x-paperless://v1/action/set_filter?tags=1,!2&tag_mode=any"))
    #expect(throws: Route.ParseError.excludedTagsNotAllowedInAnyMode) {
      try Route(from: anyOfExcludeURL)
    }

    // Test set_filter with invalid tag_mode should throw error
    let invalidModeURL = try #require(
      URL(string: "x-paperless://v1/action/set_filter?tags=1,2&tag_mode=invalid"))
    #expect(throws: Route.ParseError.invalidTagMode("invalid")) {
      try Route(from: invalidModeURL)
    }
  }

  @Test func testV2ParsingFails() throws {
    // All v2 URLs should fail to parse since Route only supports v1
    #expect(throws: Route.ParseError.unsupportedVersion("v2")) {
      try Route(from: URL(string: "x-paperless://v2/document/123")!)
    }
    #expect(throws: Route.ParseError.unsupportedVersion("v2")) {
      try Route(from: URL(string: "x-paperless://v2/action/scan")!)
    }
  }

  @Test func testParseErrorCases() throws {
    // Test missing path
    #expect(throws: Route.ParseError.missingPath) {
      try Route(from: URL(string: "x-paperless://v1")!)
    }

    // Test unsupported version with nil (missing host)
    #expect(throws: Route.ParseError.unsupportedVersion(nil)) {
      try Route(from: URL(string: "x-paperless:///document/123")!)
    }
  }

}
