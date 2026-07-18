//
//  ApiShareLinkTest.swift
//  Networking
//

import Common
import DataModel
import Foundation
import Testing

@testable import Networking

private let tz = TimeZone(secondsFromGMT: 0)!
private let decoder = makeDecoder(tz: tz)

@Suite
struct ApiShareLinkTest {
  @Test func testDecoding() throws {
    let json = """
      {
        "id": 3,
        "created": "2026-01-03T12:07:03.672917Z",
        "expiration": null,
        "slug": "5HbmQVOI1OXlSHXHq140JZsiBGNZCZKlY7zE6FVMmFTDiY6V8R",
        "document": 26,
        "file_version": "original"
      }
      """

    let data = try #require(json.data(using: .utf8))
    let shareLink = try decoder.decode(ApiShareLink.self, from: data).domain

    #expect(shareLink.id == 3)
    #expect(shareLink.slug == "5HbmQVOI1OXlSHXHq140JZsiBGNZCZKlY7zE6FVMmFTDiY6V8R")
    #expect(shareLink.document == 26)
    #expect(shareLink.fileVersion == .original)
    #expect(
      dateApprox(
        shareLink.created,
        datetime(year: 2026, month: 1, day: 3, hour: 12, minute: 7, second: 3.672917, tz: tz)))
    #expect(shareLink.expiration == nil)
  }

  @Test func testDecodingWithExpiration() throws {
    let json = """
      {
        "id": 5,
        "created": "2026-01-03T12:00:00Z",
        "expiration": "2026-02-03T12:00:00Z",
        "slug": "test-slug-123",
        "document": 1,
        "file_version": "original"
      }
      """

    let data = try #require(json.data(using: .utf8))
    let shareLink = try decoder.decode(ApiShareLink.self, from: data).domain

    #expect(shareLink.id == 5)
    #expect(shareLink.slug == "test-slug-123")
    #expect(shareLink.expiration != nil)
    #expect(
      dateApprox(
        try #require(shareLink.expiration),
        datetime(year: 2026, month: 2, day: 3, hour: 12, minute: 0, second: 0, tz: tz)))
  }

  @Test func testProtoShareLinkEncoding() throws {
    let proto = ProtoShareLink(
      document: 25,
      expiration: datetime(year: 2026, month: 2, day: 15, hour: 10, minute: 30, second: 0, tz: tz),
      fileVersion: .original)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let encoded = try encoder.encode(ApiShareLinkCreate(from: proto))
    let json = String(data: encoded, encoding: .utf8)!

    #expect(json.contains("\"document\":25"))
    #expect(json.contains("\"file_version\":\"original\""))
    #expect(json.contains("\"expiration\":"))
  }

  @Test func testProtoShareLinkEncodingWithNullExpiration() throws {
    let proto = ProtoShareLink(
      document: 30,
      expiration: nil,
      fileVersion: .archive)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let encoded = try encoder.encode(ApiShareLinkCreate(from: proto))
    let json = String(data: encoded, encoding: .utf8)!

    #expect(json.contains("\"document\":30"))
    #expect(json.contains("\"file_version\":\"archive\""))
    // When expiration is nil, it should not be included in the JSON
    #expect(!json.contains("\"expiration\""))
  }
}
