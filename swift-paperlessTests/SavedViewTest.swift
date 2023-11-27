import XCTest

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
}
