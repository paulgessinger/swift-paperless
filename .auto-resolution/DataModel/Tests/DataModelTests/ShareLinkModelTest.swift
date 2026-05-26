//
//  ShareLinkModelTest.swift
//  DataModel
//
//  Created by Assistant on 03.01.25.
//

import Common
import Foundation
import Testing

@testable import DataModel

private let tz = TimeZone(secondsFromGMT: 0)!
private let decoder = makeDecoder(tz: tz)

@Suite
struct ShareLinkModelTest {
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
    let shareLink = try decoder.decode(ShareLink.self, from: data)

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
    let shareLink = try decoder.decode(ShareLink.self, from: data)

    #expect(shareLink.id == 5)
    #expect(shareLink.slug == "test-slug-123")
    #expect(shareLink.expiration != nil)
    #expect(
      dateApprox(
        try #require(shareLink.expiration),
        datetime(year: 2026, month: 2, day: 3, hour: 12, minute: 0, second: 0, tz: tz)))
  }

  @Test func testEncoding() throws {
    let shareLink = ShareLink(
      id: 10,
      created: datetime(year: 2026, month: 1, day: 3, hour: 12, minute: 0, second: 0, tz: tz),
      expiration: nil,
      slug: "encoded-test-slug",
      document: 1,
      fileVersion: .original)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let encoded = try encoder.encode(shareLink)
    let json = String(data: encoded, encoding: .utf8)!

    #expect(json.contains("\"id\":10"))
    #expect(json.contains("\"slug\":\"encoded-test-slug\""))
    #expect(json.contains("\"created\":"))
    #expect(json.contains("\"document\":1"))
    #expect(json.contains("\"file_version\":\"original\""))
  }

  @Test func testEncodingWithExpiration() throws {
    let shareLink = ShareLink(
      id: 11,
      created: datetime(year: 2026, month: 1, day: 3, hour: 12, minute: 0, second: 0, tz: tz),
      expiration: datetime(year: 2026, month: 2, day: 3, hour: 12, minute: 0, second: 0, tz: tz),
      slug: "expiring-link",
      document: 2,
      fileVersion: .archive)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let encoded = try encoder.encode(shareLink)
    let json = String(data: encoded, encoding: .utf8)!

    #expect(json.contains("\"id\":11"))
    #expect(json.contains("\"slug\":\"expiring-link\""))
    #expect(json.contains("\"expiration\":"))
    #expect(json.contains("\"file_version\":\"archive\""))
  }

  @Test func testRoundTrip() throws {
    let original = ShareLink(
      id: 99,
      created: datetime(year: 2026, month: 1, day: 3, hour: 12, minute: 30, second: 45.5, tz: tz),
      expiration: datetime(
        year: 2026, month: 3, day: 15, hour: 10, minute: 20, second: 30.0, tz: tz),
      slug: "round-trip-test-slug",
      document: 42,
      fileVersion: .original)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let encoded = try encoder.encode(original)
    let decoded = try decoder.decode(ShareLink.self, from: encoded)

    #expect(decoded.id == original.id)
    #expect(decoded.slug == original.slug)
    #expect(decoded.document == original.document)
    #expect(decoded.fileVersion == original.fileVersion)
    #expect(dateApprox(decoded.created, original.created))
    #expect(dateApprox(try #require(decoded.expiration), try #require(original.expiration)))
  }

  @Test func testProtoShareLinkDecoding() throws {
    let json = """
      {
        "expiration": "2026-02-03T12:00:00Z",
        "document": 42,
        "file_version": "original"
      }
      """

    let data = try #require(json.data(using: .utf8))
    let proto = try decoder.decode(ProtoShareLink.self, from: data)

    #expect(proto.document == 42)
    #expect(proto.fileVersion == .original)
    #expect(proto.expiration != nil)
    #expect(
      dateApprox(
        try #require(proto.expiration),
        datetime(year: 2026, month: 2, day: 3, hour: 12, minute: 0, second: 0, tz: tz)))
  }

  @Test func testProtoShareLinkDecodingWithNullExpiration() throws {
    let json = """
      {
        "expiration": null,
        "document": 10,
        "file_version": "archive"
      }
      """

    let data = try #require(json.data(using: .utf8))
    let proto = try decoder.decode(ProtoShareLink.self, from: data)

    #expect(proto.document == 10)
    #expect(proto.fileVersion == .archive)
    #expect(proto.expiration == nil)
  }

  @Test func testProtoShareLinkEncoding() throws {
    let proto = ProtoShareLink(
      document: 25,
      expiration: datetime(year: 2026, month: 2, day: 15, hour: 10, minute: 30, second: 0, tz: tz),
      fileVersion: .original)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let encoded = try encoder.encode(proto)
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

    let encoded = try encoder.encode(proto)
    let json = String(data: encoded, encoding: .utf8)!

    #expect(json.contains("\"document\":30"))
    #expect(json.contains("\"file_version\":\"archive\""))
    // When expiration is nil, it should not be included in the JSON
    #expect(!json.contains("\"expiration\""))
  }

  @Test func testProtoShareLinkRoundTrip() throws {
    let original = ProtoShareLink(
      document: 99,
      expiration: datetime(year: 2026, month: 4, day: 1, hour: 0, minute: 0, second: 0, tz: tz),
      fileVersion: .archive)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let encoded = try encoder.encode(original)
    let decoded = try decoder.decode(ProtoShareLink.self, from: encoded)

    #expect(decoded.document == original.document)
    #expect(decoded.fileVersion == original.fileVersion)
    #expect(dateApprox(try #require(decoded.expiration), try #require(original.expiration)))
  }
}
