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

private func parseDate(_ value: String) throws -> Date {
  let formatter = DateFormatter()
  formatter.timeZone = .gmt
  formatter.dateFormat = "yyyy-MM-dd"
  guard let date = formatter.date(from: value) else {
    throw DateDecodingError.invalidDate(string: value)
  }
  return date
}

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

    // Test valid scan route with server query parameter
    let scanURL = try #require(
      URL(string: "x-paperless://v1/scan?server=\(encodedServer)"))
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

    // Test valid scan route without server
    let scanURL = try #require(URL(string: "x-paperless://v1/scan"))
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
    #expect(throws: Route.ParseError.unknownResource("invalid")) {
      try Route(from: URL(string: "x-paperless://v1/invalid")!)  // Invalid resource
    }
    #expect(throws: Route.ParseError.unknownResource("scan")) {
      try Route(from: URL(string: "x-paperless://v1/scan/extra")!)  // Extra path component
    }
  }

  @Test func testV1SetFilterAction() throws {
    // Test set_filter with multiple tags (anyOf mode, default)
    let filterURL = try #require(URL(string: "x-paperless://v1/set_filter?tags=1,2,3"))
    let filterRoute = try Route(from: filterURL)
    guard case .setFilter(let filter) = filterRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter.tags == .anyOf(ids: [1, 2, 3]))
    #expect(filterRoute.server == nil)

    // Test set_filter with single tag
    let singleTagURL = try #require(URL(string: "x-paperless://v1/set_filter?tags=42"))
    let singleTagRoute = try Route(from: singleTagURL)
    guard case .setFilter(let singleFilter) = singleTagRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(singleFilter.tags == .anyOf(ids: [42]))

    // Test set_filter with no tags parameter (nil means don't change current filter)
    let noTagsURL = try #require(URL(string: "x-paperless://v1/set_filter"))
    let noTagsRoute = try Route(from: noTagsURL)
    guard case .setFilter(let noTagsFilter) = noTagsRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(noTagsFilter.tags == nil)

    // Test set_filter with empty tags parameter (nil means don't change current filter)
    let emptyTagsURL = try #require(URL(string: "x-paperless://v1/set_filter?tags="))
    let emptyTagsRoute = try Route(from: emptyTagsURL)
    guard case .setFilter(let emptyTagsFilter) = emptyTagsRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(emptyTagsFilter.tags == nil)

    // Test set_filter with tags=none (notAssigned)
    let noneTagsURL = try #require(URL(string: "x-paperless://v1/set_filter?tags=none"))
    let noneTagsRoute = try Route(from: noneTagsURL)
    guard case .setFilter(let noneTagsFilter) = noneTagsRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(noneTagsFilter.tags == .notAssigned)

    // Test set_filter with tags=any (reset to .any)
    let anyTagsURL = try #require(URL(string: "x-paperless://v1/set_filter?tags=any"))
    let anyTagsRoute = try Route(from: anyTagsURL)
    guard case .setFilter(let anyTagsFilter) = anyTagsRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(anyTagsFilter.tags == .any)

    // Test set_filter with server only (tags nil, won't change filter)
    let serverURL = try #require(URL(string: "https://example.com"))
    let server = try #require(serverURL.stringDroppingScheme)
    let encodedServer = server.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

    let serverOnlyURL = try #require(
      URL(string: "x-paperless://v1/set_filter?server=\(encodedServer)"))
    let serverOnlyRoute = try Route(from: serverOnlyURL)
    guard case .setFilter(let serverOnlyFilter) = serverOnlyRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(serverOnlyFilter.tags == nil)
    #expect(serverOnlyRoute.server == server)

    // Test set_filter with server and tags
    let filterWithServerURL = try #require(
      URL(string: "x-paperless://v1/set_filter?server=\(encodedServer)&tags=10,20"))
    let filterWithServerRoute = try Route(from: filterWithServerURL)
    guard case .setFilter(let serverTagsFilter) = filterWithServerRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(serverTagsFilter.tags == .anyOf(ids: [10, 20]))
    #expect(filterWithServerRoute.server == server)

    // Test set_filter with tag_mode=all (allOf mode with include only)
    let allOfURL = try #require(
      URL(string: "x-paperless://v1/set_filter?tags=1,2,3&tag_mode=all"))
    let allOfRoute = try Route(from: allOfURL)
    guard case .setFilter(let allOfFilter) = allOfRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(allOfFilter.tags == .allOf(include: [1, 2, 3], exclude: []))

    // Test set_filter with tag_mode=all and excluded tags (!)
    let allOfExcludeURL = try #require(
      URL(string: "x-paperless://v1/set_filter?tags=1,2,!3,!4&tag_mode=all"))
    let allOfExcludeRoute = try Route(from: allOfExcludeURL)
    guard case .setFilter(let allOfExcludeFilter) = allOfExcludeRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(allOfExcludeFilter.tags == .allOf(include: [1, 2], exclude: [3, 4]))

    // Test set_filter with tag_mode=any and excluded tags should throw error
    let anyOfExcludeURL = try #require(
      URL(string: "x-paperless://v1/set_filter?tags=1,!2&tag_mode=any"))
    #expect(throws: Route.ParseError.excludedTagsNotAllowedInAnyMode) {
      try Route(from: anyOfExcludeURL)
    }

    // Test set_filter with invalid tag_mode should throw error
    let invalidModeURL = try #require(
      URL(string: "x-paperless://v1/set_filter?tags=1,2&tag_mode=invalid"))
    #expect(throws: Route.ParseError.invalidTagMode("invalid")) {
      try Route(from: invalidModeURL)
    }
  }

  @Test func testV1SetFilterCorrespondent() throws {
    // Test correspondent with anyOf (include IDs)
    let anyOfURL = try #require(URL(string: "x-paperless://v1/set_filter?correspondent=1,2,3"))
    let anyOfRoute = try Route(from: anyOfURL)
    guard case .setFilter(let filter) = anyOfRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter.correspondent == .anyOf(ids: [1, 2, 3]))

    // Test correspondent with noneOf (exclude IDs)
    let noneOfURL = try #require(URL(string: "x-paperless://v1/set_filter?correspondent=!1,!2"))
    let noneOfRoute = try Route(from: noneOfURL)
    guard case .setFilter(let filter2) = noneOfRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter2.correspondent == .noneOf(ids: [1, 2]))

    // Test correspondent with mixed include/exclude should throw error
    let mixedURL = try #require(URL(string: "x-paperless://v1/set_filter?correspondent=1,!2"))
    #expect(throws: Route.ParseError.mixedFilterIdsNotAllowed("correspondent")) {
      try Route(from: mixedURL)
    }

    // Test correspondent=none (notAssigned)
    let noneURL = try #require(URL(string: "x-paperless://v1/set_filter?correspondent=none"))
    let noneRoute = try Route(from: noneURL)
    guard case .setFilter(let filter3) = noneRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter3.correspondent == .notAssigned)

    // Test correspondent=any (.any)
    let anyURL = try #require(URL(string: "x-paperless://v1/set_filter?correspondent=any"))
    let anyRoute = try Route(from: anyURL)
    guard case .setFilter(let filter4) = anyRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter4.correspondent == .any)

    // Test omitted correspondent (should be nil)
    let omittedURL = try #require(URL(string: "x-paperless://v1/set_filter?tags=1"))
    let omittedRoute = try Route(from: omittedURL)
    guard case .setFilter(let filter5) = omittedRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter5.correspondent == nil)
  }

  @Test func testV1SetFilterDocumentType() throws {
    // Test document_type with anyOf
    let anyOfURL = try #require(URL(string: "x-paperless://v1/set_filter?document_type=5,6"))
    let anyOfRoute = try Route(from: anyOfURL)
    guard case .setFilter(let filter) = anyOfRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter.documentType == .anyOf(ids: [5, 6]))

    // Test document_type with noneOf
    let noneOfURL = try #require(URL(string: "x-paperless://v1/set_filter?document_type=!3,!4"))
    let noneOfRoute = try Route(from: noneOfURL)
    guard case .setFilter(let filter2) = noneOfRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter2.documentType == .noneOf(ids: [3, 4]))

    // Test document_type=none
    let noneURL = try #require(URL(string: "x-paperless://v1/set_filter?document_type=none"))
    let noneRoute = try Route(from: noneURL)
    guard case .setFilter(let filter3) = noneRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter3.documentType == .notAssigned)

    // Test document_type=any
    let anyURL = try #require(URL(string: "x-paperless://v1/set_filter?document_type=any"))
    let anyRoute = try Route(from: anyURL)
    guard case .setFilter(let filter4) = anyRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter4.documentType == .any)
  }

  @Test func testV1SetFilterStoragePath() throws {
    // Test storage_path with anyOf
    let anyOfURL = try #require(URL(string: "x-paperless://v1/set_filter?storage_path=10,20,30"))
    let anyOfRoute = try Route(from: anyOfURL)
    guard case .setFilter(let filter) = anyOfRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter.storagePath == .anyOf(ids: [10, 20, 30]))

    // Test storage_path with noneOf
    let noneOfURL = try #require(URL(string: "x-paperless://v1/set_filter?storage_path=!5"))
    let noneOfRoute = try Route(from: noneOfURL)
    guard case .setFilter(let filter2) = noneOfRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter2.storagePath == .noneOf(ids: [5]))

    // Test storage_path=none
    let noneURL = try #require(URL(string: "x-paperless://v1/set_filter?storage_path=none"))
    let noneRoute = try Route(from: noneURL)
    guard case .setFilter(let filter3) = noneRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter3.storagePath == .notAssigned)

    // Test storage_path=any
    let anyURL = try #require(URL(string: "x-paperless://v1/set_filter?storage_path=any"))
    let anyRoute = try Route(from: anyURL)
    guard case .setFilter(let filter4) = anyRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter4.storagePath == .any)
  }

  @Test func testV1SetFilterOwner() throws {
    // Test owner with anyOf
    let anyOfURL = try #require(URL(string: "x-paperless://v1/set_filter?owner=7,8,9"))
    let anyOfRoute = try Route(from: anyOfURL)
    guard case .setFilter(let filter) = anyOfRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter.owner == .anyOf(ids: [7, 8, 9]))

    // Test owner with noneOf
    let noneOfURL = try #require(URL(string: "x-paperless://v1/set_filter?owner=!10,!11"))
    let noneOfRoute = try Route(from: noneOfURL)
    guard case .setFilter(let filter2) = noneOfRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter2.owner == .noneOf(ids: [10, 11]))

    // Test owner=none
    let noneURL = try #require(URL(string: "x-paperless://v1/set_filter?owner=none"))
    let noneRoute = try Route(from: noneURL)
    guard case .setFilter(let filter3) = noneRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter3.owner == .notAssigned)

    // Test owner=any
    let anyURL = try #require(URL(string: "x-paperless://v1/set_filter?owner=any"))
    let anyRoute = try Route(from: anyURL)
    guard case .setFilter(let filter4) = anyRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter4.owner == .any)
  }

  @Test func testV1SetFilterCombinations() throws {
    // Test combining multiple filters
    let combinedURL = try #require(
      URL(
        string: "x-paperless://v1/set_filter?correspondent=1,2&document_type=3&tags=4,5&search=test"
      ))
    let combinedRoute = try Route(from: combinedURL)
    guard case .setFilter(let filter) = combinedRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter.correspondent == .anyOf(ids: [1, 2]))
    #expect(filter.documentType == .anyOf(ids: [3]))
    #expect(filter.tags == .anyOf(ids: [4, 5]))
    #expect(filter.searchText == "test")

    // Filters not specified should be nil
    #expect(filter.storagePath == nil)
    #expect(filter.owner == nil)
    #expect(filter.searchMode == nil)
  }

  @Test func testV1SetFilterSearch() throws {
    // Test search text only
    let searchOnlyURL = try #require(URL(string: "x-paperless://v1/set_filter?search=invoice"))
    let searchOnlyRoute = try Route(from: searchOnlyURL)
    guard case .setFilter(let filter) = searchOnlyRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter.searchText == "invoice")
    #expect(filter.searchMode == nil)

    // Test search with title mode
    let titleModeURL = try #require(
      URL(string: "x-paperless://v1/set_filter?search=receipt&search_mode=title"))
    let titleModeRoute = try Route(from: titleModeURL)
    guard case .setFilter(let filter2) = titleModeRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter2.searchText == "receipt")
    #expect(filter2.searchMode == .title)

    // Test search with content mode
    let contentModeURL = try #require(
      URL(string: "x-paperless://v1/set_filter?search=contract&search_mode=content"))
    let contentModeRoute = try Route(from: contentModeURL)
    guard case .setFilter(let filter3) = contentModeRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter3.searchText == "contract")
    #expect(filter3.searchMode == .content)

    // Test search with title_content mode
    let titleContentURL = try #require(
      URL(string: "x-paperless://v1/set_filter?search=test&search_mode=title_content"))
    let titleContentRoute = try Route(from: titleContentURL)
    guard case .setFilter(let filter4) = titleContentRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter4.searchText == "test")
    #expect(filter4.searchMode == .titleContent)

    // Test search with advanced mode
    let advancedURL = try #require(
      URL(string: "x-paperless://v1/set_filter?search=query&search_mode=advanced"))
    let advancedRoute = try Route(from: advancedURL)
    guard case .setFilter(let filter5) = advancedRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter5.searchText == "query")
    #expect(filter5.searchMode == .advanced)

    // Test invalid search mode
    let invalidURL = try #require(
      URL(string: "x-paperless://v1/set_filter?search=test&search_mode=invalid"))
    #expect(throws: Route.ParseError.invalidSearchMode("invalid")) {
      try Route(from: invalidURL)
    }
  }

  @Test func testV1SetFilterDates() throws {
    let rangeURL = try #require(
      URL(
        string:
          "x-paperless://v1/set_filter?date_created=within_1w&date_added=within_1m&date_modified=within_1y"
      )
    )
    let rangeRoute = try Route(from: rangeURL)
    guard case .setFilter(let rangeFilter) = rangeRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(rangeFilter.dateCreated == .range(.within(num: -1, interval: .week)))
    #expect(rangeFilter.dateAdded == .range(.within(num: -1, interval: .month)))
    #expect(rangeFilter.dateModified == .range(.within(num: -1, interval: .year)))

    let betweenURL = try #require(
      URL(
        string:
          "x-paperless://v1/set_filter?date_created_from=2024-01-01&date_created_to=2024-12-31"
      )
    )
    let betweenRoute = try Route(from: betweenURL)
    guard case .setFilter(let betweenFilter) = betweenRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(
      betweenFilter.dateCreated
        == .between(start: try parseDate("2024-01-01"), end: try parseDate("2024-12-31"))
    )
    #expect(betweenFilter.dateAdded == nil)
    #expect(betweenFilter.dateModified == nil)

    let openEndedURL = try #require(
      URL(string: "x-paperless://v1/set_filter?date_added_from=2024-02-02")
    )
    let openEndedRoute = try Route(from: openEndedURL)
    guard case .setFilter(let openEndedFilter) = openEndedRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(
      openEndedFilter.dateAdded == .between(start: try parseDate("2024-02-02"), end: nil)
    )

    let anyURL = try #require(URL(string: "x-paperless://v1/set_filter?date_modified=any"))
    let anyRoute = try Route(from: anyURL)
    guard case .setFilter(let anyFilter) = anyRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(anyFilter.dateModified == .any)

    let invalidURL = try #require(
      URL(string: "x-paperless://v1/set_filter?date_created=today")
    )
    #expect(throws: Route.ParseError.invalidDateFormat("today")) {
      try Route(from: invalidURL)
    }

    let invalidWithinURL = try #require(
      URL(string: "x-paperless://v1/set_filter?date_created=within_2w")
    )
    #expect(throws: Route.ParseError.invalidDateFormat("within_2w")) {
      try Route(from: invalidWithinURL)
    }

    let invalidWithinDaysURL = try #require(
      URL(string: "x-paperless://v1/set_filter?date_created=within_7d")
    )
    #expect(throws: Route.ParseError.invalidDateFormat("within_7d")) {
      try Route(from: invalidWithinDaysURL)
    }
  }

  @Test func testV1SetFilterSort() throws {
    let sortURL = try #require(
      URL(string: "x-paperless://v1/set_filter?sort_field=created&sort_order=asc")
    )
    let sortRoute = try Route(from: sortURL)
    guard case .setFilter(let sortFilter) = sortRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(sortFilter.sortField == .created)
    #expect(sortFilter.sortOrder == .ascending)

    let rawURL = try #require(
      URL(string: "x-paperless://v1/set_filter?sort_field=correspondent__name&sort_order=desc")
    )
    let rawRoute = try Route(from: rawURL)
    guard case .setFilter(let rawFilter) = rawRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(rawFilter.sortField == .correspondent)
    #expect(rawFilter.sortOrder == .descending)

    let aliasURL = try #require(
      URL(string: "x-paperless://v1/set_filter?sort_field=document_type&sort_order=desc")
    )
    let aliasRoute = try Route(from: aliasURL)
    guard case .setFilter(let aliasFilter) = aliasRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(aliasFilter.sortField == .documentType)
    #expect(aliasFilter.sortOrder == .descending)

    let customURL = try #require(
      URL(string: "x-paperless://v1/set_filter?sort_field=custom_field_12")
    )
    let customRoute = try Route(from: customURL)
    guard case .setFilter(let customFilter) = customRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(customFilter.sortField == .customField(12))
    #expect(customFilter.sortOrder == nil)

    let invalidURL = try #require(
      URL(string: "x-paperless://v1/set_filter?sort_field=not_a_field")
    )
    #expect(throws: Route.ParseError.invalidSortField("not_a_field")) {
      try Route(from: invalidURL)
    }
  }

  @Test func testV1ClearFilterAction() throws {
    // Test clear_filter without server
    let clearFilterURL = try #require(URL(string: "x-paperless://v1/clear_filter"))
    let clearFilterRoute = try Route(from: clearFilterURL)
    #expect(clearFilterRoute.action == .clearFilter)
    #expect(clearFilterRoute.server == nil)

    // Test clear_filter with server
    let serverURL = try #require(URL(string: "https://example.com"))
    let server = try #require(serverURL.stringDroppingScheme)
    let encodedServer = server.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

    let clearFilterWithServerURL = try #require(
      URL(string: "x-paperless://v1/clear_filter?server=\(encodedServer)"))
    let clearFilterWithServerRoute = try Route(from: clearFilterWithServerURL)
    #expect(clearFilterWithServerRoute.action == .clearFilter)
    #expect(clearFilterWithServerRoute.server == server)

    // Test clear_filter with extra path component should fail
    #expect(throws: Route.ParseError.unknownResource("clear_filter")) {
      try Route(from: URL(string: "x-paperless://v1/clear_filter/extra")!)
    }
  }

  @Test func testV2ParsingFails() throws {
    // All v2 URLs should fail to parse since Route only supports v1
    #expect(throws: Route.ParseError.unsupportedVersion("v2")) {
      try Route(from: URL(string: "x-paperless://v2/document/123")!)
    }
    #expect(throws: Route.ParseError.unsupportedVersion("v2")) {
      try Route(from: URL(string: "x-paperless://v2/scan")!)
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

  @Test func testV1SetFilterAsn() throws {
    // Test asn with equalTo
    let equalToURL = try #require(URL(string: "x-paperless://v1/set_filter?asn=123"))
    let equalToRoute = try Route(from: equalToURL)
    guard case .setFilter(let filter) = equalToRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(filter.asn == .equalTo(123))

    // Test asn with greaterThan
    let greaterThanURL = try #require(URL(string: "x-paperless://v1/set_filter?asn_gt=100"))
    let greaterThanRoute = try Route(from: greaterThanURL)
    guard case .setFilter(let gtFilter) = greaterThanRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(gtFilter.asn == .greaterThan(100))

    // Test asn with lessThan
    let lessThanURL = try #require(URL(string: "x-paperless://v1/set_filter?asn_lt=200"))
    let lessThanRoute = try Route(from: lessThanURL)
    guard case .setFilter(let ltFilter) = lessThanRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(ltFilter.asn == .lessThan(200))

    // Test asn with isNull
    let isNullURL = try #require(URL(string: "x-paperless://v1/set_filter?asn=null"))
    let isNullRoute = try Route(from: isNullURL)
    guard case .setFilter(let nullFilter) = isNullRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(nullFilter.asn == .isNull)

    // Test asn with isNotNull
    let isNotNullURL = try #require(URL(string: "x-paperless://v1/set_filter?asn=not_null"))
    let isNotNullRoute = try Route(from: isNotNullURL)
    guard case .setFilter(let notNullFilter) = isNotNullRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(notNullFilter.asn == .isNotNull)

    // Test asn with any
    let anyURL = try #require(URL(string: "x-paperless://v1/set_filter?asn=any"))
    let anyRoute = try Route(from: anyURL)
    guard case .setFilter(let anyFilter) = anyRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(anyFilter.asn == .any)

    // Test without asn parameter (should be nil)
    let noAsnURL = try #require(URL(string: "x-paperless://v1/set_filter?tags=1,2"))
    let noAsnRoute = try Route(from: noAsnURL)
    guard case .setFilter(let noAsnFilter) = noAsnRoute.action else {
      Issue.record("Expected setFilter action")
      return
    }
    #expect(noAsnFilter.asn == nil)

    // Test invalid asn value throws error
    let invalidURL = try #require(URL(string: "x-paperless://v1/set_filter?asn=invalid"))
    #expect(throws: Route.ParseError.invalidAsnValue("invalid")) {
      try Route(from: invalidURL)
    }

    // Test invalid asn_gt value throws error
    let invalidGtURL = try #require(URL(string: "x-paperless://v1/set_filter?asn_gt=abc"))
    #expect(throws: Route.ParseError.invalidAsnValue("abc")) {
      try Route(from: invalidGtURL)
    }

    // Test invalid asn_lt value throws error
    let invalidLtURL = try #require(URL(string: "x-paperless://v1/set_filter?asn_lt=xyz"))
    #expect(throws: Route.ParseError.invalidAsnValue("xyz")) {
      try Route(from: invalidLtURL)
    }
  }

}
