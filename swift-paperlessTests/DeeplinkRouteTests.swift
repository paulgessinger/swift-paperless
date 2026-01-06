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

  @Test func testV1SetFilterAction() throws {
    // Test set_filter with multiple tags (anyOf mode, default)
    let filterURL = try #require(URL(string: "x-paperless://v1/action/set_filter?tags=1,2,3"))
    let filterRoute = Route(from: filterURL)
    #expect(filterRoute != nil)
    #expect(filterRoute?.action == .setFilter(tags: .anyOf(ids: [1, 2, 3])))
    #expect(filterRoute?.server == nil)

    // Test set_filter with single tag
    let singleTagURL = try #require(URL(string: "x-paperless://v1/action/set_filter?tags=42"))
    let singleTagRoute = Route(from: singleTagURL)
    #expect(singleTagRoute != nil)
    #expect(singleTagRoute?.action == .setFilter(tags: .anyOf(ids: [42])))

    // Test set_filter with no tags parameter (nil means don't change current filter)
    let noTagsURL = try #require(URL(string: "x-paperless://v1/action/set_filter"))
    let noTagsRoute = Route(from: noTagsURL)
    #expect(noTagsRoute != nil)
    #expect(noTagsRoute?.action == .setFilter(tags: nil))

    // Test set_filter with tags=none (notAssigned)
    let noneTagsURL = try #require(URL(string: "x-paperless://v1/action/set_filter?tags=none"))
    let noneTagsRoute = Route(from: noneTagsURL)
    #expect(noneTagsRoute != nil)
    #expect(noneTagsRoute?.action == .setFilter(tags: .notAssigned))

    // Test set_filter with server only (tags nil, won't change filter)
    let serverURL = try #require(URL(string: "https://example.com"))
    let server = try #require(serverURL.stringDroppingScheme)
    let encodedServer = server.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

    let serverOnlyURL = try #require(
      URL(string: "x-paperless://v1/action/set_filter?server=\(encodedServer)"))
    let serverOnlyRoute = Route(from: serverOnlyURL)
    #expect(serverOnlyRoute != nil)
    #expect(serverOnlyRoute?.action == .setFilter(tags: nil))
    #expect(serverOnlyRoute?.server == server)

    // Test set_filter with server and tags
    let filterWithServerURL = try #require(
      URL(string: "x-paperless://v1/action/set_filter?server=\(encodedServer)&tags=10,20"))
    let filterWithServerRoute = Route(from: filterWithServerURL)
    #expect(filterWithServerRoute != nil)
    #expect(filterWithServerRoute?.action == .setFilter(tags: .anyOf(ids: [10, 20])))
    #expect(filterWithServerRoute?.server == server)

    // Test set_filter with tag_mode=all (allOf mode with include only)
    let allOfURL = try #require(
      URL(string: "x-paperless://v1/action/set_filter?tags=1,2,3&tag_mode=all"))
    let allOfRoute = Route(from: allOfURL)
    #expect(allOfRoute != nil)
    #expect(allOfRoute?.action == .setFilter(tags: .allOf(include: [1, 2, 3], exclude: [])))

    // Test set_filter with tag_mode=all and excluded tags (!)
    let allOfExcludeURL = try #require(
      URL(string: "x-paperless://v1/action/set_filter?tags=1,2,!3,!4&tag_mode=all"))
    let allOfExcludeRoute = Route(from: allOfExcludeURL)
    #expect(allOfExcludeRoute != nil)
    #expect(
      allOfExcludeRoute?.action == .setFilter(tags: .allOf(include: [1, 2], exclude: [3, 4])))

    // Test set_filter with tag_mode=any and excluded tags should fail (invalid)
    let anyOfExcludeURL = try #require(
      URL(string: "x-paperless://v1/action/set_filter?tags=1,!2&tag_mode=any"))
    let anyOfExcludeRoute = Route(from: anyOfExcludeURL)
    #expect(anyOfExcludeRoute == nil)

    // Test set_filter with invalid tag_mode should fail
    let invalidModeURL = try #require(
      URL(string: "x-paperless://v1/action/set_filter?tags=1,2&tag_mode=invalid"))
    let invalidModeRoute = Route(from: invalidModeURL)
    #expect(invalidModeRoute == nil)
  }

  @Test func testV2ParsingFails() throws {
    // All v2 URLs should fail to parse since Route only supports v1
    #expect(Route(from: URL(string: "x-paperless://v2/document/123")!) == nil)
    #expect(Route(from: URL(string: "x-paperless://v2/action/scan")!) == nil)
  }

}
