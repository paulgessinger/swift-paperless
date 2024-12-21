import XCTest

import DataModel

final class SavedViewTest: XCTestCase {
    func testDecoding() throws {
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

            let result = try JSONDecoder().decode(SavedView.self, from: input)
            XCTAssertEqual(result.id, 5)
            XCTAssertEqual(result.name, "Aktien Kauf")
            XCTAssertEqual(result.showOnDashboard, false)
            XCTAssertEqual(result.showInSidebar, false)
            XCTAssertEqual(result.sortField, .created)
            XCTAssertEqual(result.sortOrder, .descending)
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

            let result = try JSONDecoder().decode(SavedView.self, from: input)
            XCTAssertEqual(result.id, 5)
            XCTAssertEqual(result.name, "Aktien Kauf")
            XCTAssertEqual(result.showOnDashboard, false)
            XCTAssertEqual(result.showInSidebar, false)
            XCTAssertEqual(result.sortField, .created)
            XCTAssertEqual(result.sortOrder, .ascending)
        }
    }

    // See https://github.com/paulgessinger/swift-paperless/issues/108
    func testDecodingNilSortField() throws {
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

        let result = try JSONDecoder().decode(SavedView.self, from: input)
        XCTAssertEqual(result.id, 1)
        XCTAssertEqual(result.name, "Inbox")
        XCTAssertEqual(result.showOnDashboard, true)
        XCTAssertEqual(result.showInSidebar, true)
        XCTAssertEqual(result.sortField, .added)
        XCTAssertEqual(result.sortOrder, .ascending)
    }

    // See https://github.com/paulgessinger/swift-paperless/issues/108
    func testDecodingWithStringSortField() throws {
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

        let result = try JSONDecoder().decode(SavedView.self, from: input)
        XCTAssertEqual(result.id, 1)
        XCTAssertEqual(result.name, "inbox")
        XCTAssertEqual(result.showOnDashboard, true)
        XCTAssertEqual(result.showInSidebar, true)
        XCTAssertEqual(result.sortField, .score)
        XCTAssertEqual(result.sortOrder, .ascending)
    }
}
