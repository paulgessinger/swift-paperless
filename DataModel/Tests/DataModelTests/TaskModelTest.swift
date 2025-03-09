//
//  TaskModelTest.swift
//  DataModel
//
//  Created by Assistant on 03.01.25.
//

import Common
@testable import DataModel
import Foundation
import Testing

private let tz = TimeZone(secondsFromGMT: 60 * 60)!
private let decoder = makeDecoder(tz: tz)

@Suite
struct TaskModelTest {
    @Test func testDecoding() throws {
        let data = try #require(testData("Data/tasks.json"))
        let tasks = try decoder.decode([PaperlessTask].self, from: data)

        // Test successful task
        #expect(tasks[0].id == 3438)
        #expect(tasks[0].taskId == UUID(uuidString: "373a38ca-5f44-46f5-9466-32e55e103533"))
        #expect(tasks[0].taskFileName == "sample_document_001.pdf")
        #expect(try dateApprox(#require(tasks[0].dateCreated), datetime(year: 2025, month: 1, day: 3, hour: 10, minute: 45, second: 2, tz: tz)))
        #expect(try dateApprox(#require(tasks[0].dateDone), datetime(year: 2025, month: 1, day: 3, hour: 10, minute: 45, second: 4, tz: tz)))
        #expect(tasks[0].type == "file")
        #expect(tasks[0].status == .SUCCESS)
        #expect(tasks[0].result == "Success. New document id 2737 created")
        #expect(tasks[0].acknowledged == false)
        #expect(tasks[0].relatedDocument == "2737")
        #expect(tasks[0].isActive == false)

        // Test pending task
        #expect(tasks[1].id == 3437)
        #expect(tasks[1].status == .PENDING)
        #expect(tasks[1].result == nil)
        #expect(tasks[1].relatedDocument == nil)
        #expect(tasks[1].isActive == true)

        // Test started task
        #expect(tasks[2].status == .STARTED)
        #expect(tasks[2].result == "Processing document...")
        #expect(tasks[2].isActive == true)

        // Test failed task
        #expect(tasks[3].status == .FAILURE)
        #expect(tasks[3].result == "Document processing failed: invalid file format")
        #expect(tasks[3].isActive == false)

        // Test retry task
        #expect(tasks[4].status == .RETRY)
        #expect(tasks[4].result == "Retrying after temporary error")
        #expect(tasks[4].isActive == true)
    }
}
