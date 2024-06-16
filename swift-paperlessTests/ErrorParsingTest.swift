//
//  ErrorParsingTest.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 07.05.2024.
//

import XCTest

final class ErrorParsingTest: XCTestCase {
    func testDuplicateParsing() throws {
        let task = PaperlessTask(id: 1, taskId: .init(), taskFileName: "2015-02-01 Car Garage Health Employee Data Collection Form.pdf", type: .file, status: .FAILURE,
                                 result: "2015-02-01 Car Garage Health Employee Data Collection Form.pdf: Not consuming 2015-02-01 Car Garage Health Employee Data Collection Form.pdf: It is a duplicate of 2015-02-01 Car Garage Health Employee Data Collection Form.pdf (#28)",
                                 acknowledged: false)

        XCTAssertEqual(task.localizedResult, String(localized: .tasks(.errorDuplicate)(task.taskFileName!)))
    }
}
