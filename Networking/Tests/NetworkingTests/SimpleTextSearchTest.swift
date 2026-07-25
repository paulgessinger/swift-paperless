//
//  SimpleTextSearchTest.swift
//  Networking
//
//  Version gating for the Tantivy-backed `text` document filter parameter,
//  which paperless-ngx 3.0 introduced as the replacement for `title_content`.
//

import Common
import DataModel
import Foundation
import Testing

@testable import Networking

@Suite("Tantivy simple search feature gate")
struct SimpleTextSearchTest {
  private static let searchState = FilterState.empty.with {
    $0.searchMode = .titleContent
    $0.searchText = "invoice"
  }

  @Test(
    "Backends without the feature keep receiving `title_content`",
    .bug(id: "642"),
    arguments: [
      Version(1, 14, 1), Version(2, 0, 0), Version(2, 20, 0), Version(2, 99, 0),
    ])
  func unsupportedOnOlderBackends(version: Version) {
    // Older backends silently ignore unknown query parameters, so sending
    // `text` there would drop the filter and return every document.
    #expect(!BackendFeature.tantivySimpleSearch.isSupported(on: version, api: 9))
  }

  @Test(
    "Backends at 3.0 / API v10 or newer support `text`",
    .bug(id: "642"),
    arguments: [
      (Version(3, 0, 0), UInt(10)),
      (Version(3, 0, 2), UInt(10)),
      // Version string unavailable but the API version says v10.
      (Version(2, 20, 0), UInt(10)),
      // API version unavailable but the version string says 3.x.
      (Version(3, 1, 0), UInt(9)),
    ])
  func supportedOnNewerBackends(version: Version, api: UInt) {
    #expect(BackendFeature.tantivySimpleSearch.isSupported(on: version, api: api))
  }

  @Test(
    "The document endpoint defaults to the parameter every backend understands", .bug(id: "642"))
  func endpointDefaultsToLegacy() {
    let endpoint = Endpoint.documents(page: 1, filter: Self.searchState)
    #expect(endpoint.queryItems.contains(URLQueryItem(name: "title_content", value: "invoice")))
    #expect(!endpoint.queryItems.contains { $0.name == "text" })
  }

  @Test("The document endpoint emits `text` when asked for the 3.0 encoding", .bug(id: "642"))
  func endpointUsesTextForTantivy() {
    let endpoint = Endpoint.documents(page: 1, filter: Self.searchState, searchApi: .tantivy)
    #expect(endpoint.queryItems.contains(URLQueryItem(name: "text", value: "invoice")))
    #expect(!endpoint.queryItems.contains { $0.name == "title_content" })
  }

  @Test("Switching the encoding leaves the rest of the URL alone", .bug(id: "642"))
  func endpointIsOtherwiseUnchanged() throws {
    let base = URL(string: "https://example.com")!

    func queryNames(_ searchApi: FilterState.SearchApi) throws -> Set<String> {
      let url = try #require(
        Endpoint.documents(page: 3, filter: Self.searchState, pageSize: 25, searchApi: searchApi)
          .url(url: base))
      let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
      return Set((components.queryItems ?? []).map(\.name))
    }

    let legacy = try queryNames(.legacy)
    let tantivy = try queryNames(.tantivy)

    #expect(legacy.subtracting(tantivy) == ["title_content"])
    #expect(tantivy.subtracting(legacy) == ["text"])
    #expect(legacy.intersection(tantivy) == ["page", "page_size", "truncate_content", "ordering"])
  }
}
