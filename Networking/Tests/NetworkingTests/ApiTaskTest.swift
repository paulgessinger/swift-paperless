import Common
import DataModel
import Foundation
import Testing

@testable import Networking

private let tz = TimeZone(secondsFromGMT: 60 * 60)!
private let decoder = makeDecoder(tz: tz)

@Suite
struct ApiTaskTest {
  @Test func testDecoding() throws {
    let data = try #require(testData("Data/tasks.json"))
    let tasks = try decoder.decode([ApiTask].self, from: data).map(\.domain)

    #expect(tasks[0].id == 3438)
    #expect(tasks[0].taskId == UUID(uuidString: "373a38ca-5f44-46f5-9466-32e55e103533"))
    #expect(tasks[0].taskFileName == "sample_document_001.pdf")
    #expect(
      try dateApprox(
        #require(tasks[0].dateCreated),
        datetime(year: 2025, month: 1, day: 3, hour: 10, minute: 45, second: 2, tz: tz)))
    #expect(
      try dateApprox(
        #require(tasks[0].dateDone),
        datetime(year: 2025, month: 1, day: 3, hour: 10, minute: 45, second: 4, tz: tz)))
    #expect(tasks[0].type == "file")
    #expect(tasks[0].status == TaskStatus.SUCCESS)
    #expect(tasks[0].result == "Success. New document id 2737 created")
    #expect(tasks[0].acknowledged == false)
    #expect(tasks[0].relatedDocument == "2737")
    #expect(tasks[0].isActive == false)

    #expect(tasks[1].id == 3437)
    #expect(tasks[1].status == TaskStatus.PENDING)
    #expect(tasks[1].result == nil)
    #expect(tasks[1].relatedDocument == nil)
    #expect(tasks[1].isActive == true)

    #expect(tasks[2].status == TaskStatus.STARTED)
    #expect(tasks[2].result == "Processing document...")
    #expect(tasks[2].isActive == true)

    #expect(tasks[3].status == TaskStatus.FAILURE)
    #expect(tasks[3].result == "Document processing failed: invalid file format")
    #expect(tasks[3].isActive == false)

    #expect(tasks[4].status == TaskStatus.RETRY)
    #expect(tasks[4].result == "Retrying after temporary error")
    #expect(tasks[4].isActive == true)
  }
}
