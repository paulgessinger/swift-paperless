import Common
import Foundation
import Testing

@testable import DataModel

private let decoder = JSONDecoder()

@Suite
struct SavedViewTest {
  @Test func testDecoding() throws {
    do {
      let input = """
        {
            "id": 5,
            "name": "Aktien Kauf",
            "show_on_dashboard": false,
            "show_in_sidebar": false,
            "sort_field": "created",
            "sort_reverse": true,
            "filter_rules": [
                {
                    "rule_type": 19,
                    "value": "Abrechnung Kauf"
                },
                {
                    "rule_type": 3,
                    "value": "37"
                }
            ]
        }
        """.data(using: .utf8)!

      let result = try decoder.decode(SavedView.self, from: input)
      #expect(result.id == 5)
      #expect(result.name == "Aktien Kauf")
      #expect(result.showOnDashboard == false)
      #expect(result.showInSidebar == false)
      #expect(result.sortField == .created)
      #expect(result.sortOrder == .descending)
    }

    do {
      let input = """
        {
            "id": 5,
            "name": "Aktien Kauf",
            "show_on_dashboard": false,
            "show_in_sidebar": false,
            "sort_field": "created",
            "sort_reverse": false,
            "filter_rules": [
                {
                    "rule_type": 19,
                    "value": "Abrechnung Kauf"
                },
                {
                    "rule_type": 3,
                    "value": "37"
                }
            ]
        }
        """.data(using: .utf8)!

      let result = try decoder.decode(SavedView.self, from: input)
      #expect(result.id == 5)
      #expect(result.name == "Aktien Kauf")
      #expect(result.showOnDashboard == false)
      #expect(result.showInSidebar == false)
      #expect(result.sortField == .created)
      #expect(result.sortOrder == .ascending)
    }
  }

  // See https://github.com/paulgessinger/swift-paperless/issues/108
  @Test func testDecodingNilSortField() throws {
    let input = """
      {
        "id": 1,
        "name": "Inbox",
        "show_on_dashboard": true,
        "show_in_sidebar": true,
        "sort_field": null,
        "sort_reverse": false,
        "filter_rules": [
          {
            "rule_type": 6,
            "value": "1"
          }
        ],
        "page_size": null,
        "display_mode": null,
        "display_fields": null,
        "owner": 3,
        "user_can_change": true
      }
      """.data(using: .utf8)!

    let result = try decoder.decode(SavedView.self, from: input)
    #expect(result.id == 1)
    #expect(result.name == "Inbox")
    #expect(result.showOnDashboard == true)
    #expect(result.showInSidebar == true)
    #expect(result.sortField == nil)
    #expect(result.sortOrder == .ascending)
  }

  // See https://github.com/paulgessinger/swift-paperless/issues/108
  @Test func testDecodingWithScoreSortField() throws {
    let input = """
      {
        "id": 1,
        "name": "inbox",
        "show_on_dashboard": true,
        "show_in_sidebar": true,
        "sort_field": "score",
        "sort_reverse": false,
        "filter_rules": [
          {
            "rule_type": 20,
            "value": "inbox"
          }
        ],
        "page_size": null,
        "display_mode": null,
        "display_fields": null,
        "owner": 3,
        "user_can_change": true
      }
      """.data(using: .utf8)!

    let result = try decoder.decode(SavedView.self, from: input)
    #expect(result.id == 1)
    #expect(result.name == "inbox")
    #expect(result.showOnDashboard == true)
    #expect(result.showInSidebar == true)
    #expect(result.sortField == .score)
    #expect(result.sortOrder == .ascending)
  }

  @Test func testDecodingWithInvalidSortField() throws {
    let input = """
      {
        "id": 1,
        "name": "inbox",
        "show_on_dashboard": true,
        "show_in_sidebar": true,
        "sort_field": "invalid_field",
        "sort_reverse": false,
        "filter_rules": [
          {
            "rule_type": 20,
            "value": "inbox"
          }
        ]
      }
      """.data(using: .utf8)!

    let result = try decoder.decode(SavedView.self, from: input)
    #expect(result.id == 1)
    #expect(result.name == "inbox")
    #expect(result.showOnDashboard == true)
    #expect(result.showInSidebar == true)
    #expect(result.sortField == .other("invalid_field"))
    #expect(result.sortOrder == .ascending)
  }

  /// Backend v3+ removed show_on_dashboard and show_in_sidebar; they default to false when absent.
  @Test func testDecodingV3WithoutShowFields() throws {
    let data = try #require(testData("Data/SavedView/saved_view_perms_v3.json"))
    let result = try decoder.decode(ListResponse<SavedView>.self, from: data)

    #expect(result.count == 7)
    #expect(result.results.count == 7)

    let first = try #require(result.results.first)
    #expect(first.id == 7)
    #expect(first.name == "ASN: 1")
    #expect(first.showOnDashboard == false)
    #expect(first.showInSidebar == false)
    #expect(first.sortField == .other("custom_field_1"))
    #expect(first.sortOrder == .descending)
    #expect(first.filterRules.count == 1)
  }
}
