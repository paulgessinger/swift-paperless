//
//  swift_paperlessTests.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 13.02.23.
//

@testable import swift_paperless
import XCTest

final class swift_paperlessTests: XCTestCase {
//    let df = {
//        ISO8601DateFormatter()
    ////        let _df = DateFormatter()
//        ////        _df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSZZZZZ"
    ////            return _df
//    }()

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testDateDecoding() throws {
        let input = "\"2023-02-25T10:13:54.057805+01:00\"".data(using: .utf8)!
        let date = try decoder.decode(Date.self, from: input)
        XCTAssertNotNil(date)

        let input2 = "\"2023-02-18T00:00:00+01:00\"".data(using: .utf8)!
        let date2 = try decoder.decode(Date.self, from: input2)
        XCTAssertNotNil(date2)
    }
}
