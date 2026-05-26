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
    let tasks = try decoder.decode([ApiTaskV9].self, from: data).map(\.domain)

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

  @Test func testDecodingV10Paginated() throws {
    let data = try #require(testData("Data/tasks_v10_paginated.json"))
    let tasks = try decoder.decode(ListResponse<ApiTaskV10>.self, from: data).results.map(\.domain)
    #expect(tasks.count == 2)
    #expect(tasks[0].id == 2)
    #expect(tasks[1].id == 1)
  }

  @Test func testDecodingV10() throws {
    let data = try #require(testData("Data/tasks_v10.json"))
    let tasks = try decoder.decode([ApiTaskV10].self, from: data).map(\.domain)

    #expect(tasks[0].id == 2)
    #expect(tasks[0].taskId == UUID(uuidString: "07dd974d-be9e-4a2d-9be2-0cbe183a2069"))
    #expect(tasks[0].taskFileName == "slides-with-plans.pdf")
    #expect(tasks[0].taskName == "consume_file")
    #expect(tasks[0].type == "web_ui")
    #expect(
      try dateApprox(
        #require(tasks[0].dateCreated),
        datetime(year: 2026, month: 4, day: 18, hour: 8, minute: 46, second: 56.306241, tz: tz)))
    #expect(
      try dateApprox(
        #require(tasks[0].dateDone),
        datetime(year: 2026, month: 4, day: 18, hour: 8, minute: 46, second: 58.981436, tz: tz)))
    #expect(tasks[0].status == TaskStatus.SUCCESS)
    #expect(tasks[0].result == "Success. New document id 29 created")
    #expect(tasks[0].acknowledged == false)
    #expect(tasks[0].relatedDocument == "29")
    #expect(tasks[0].isActive == false)

    #expect(tasks[1].id == 1)
    #expect(tasks[1].taskId == UUID(uuidString: "f15a52a7-5af2-4944-b8b7-5be1a5231096"))
    #expect(tasks[1].taskFileName == "colliderml_overview.pdf")
    #expect(tasks[1].status == TaskStatus.PENDING)
    #expect(tasks[1].dateDone == nil)
    #expect(tasks[1].result == nil)
    #expect(tasks[1].relatedDocument == nil)
    #expect(tasks[1].isActive == true)
  }

  @Test(arguments: [
    // Historic form, no trailing period.
    (
      "2015-02-01 Form.pdf: Not consuming 2015-02-01 Form.pdf: It is a duplicate of 2015-02-01 Form.pdf (#28)",
      UInt(28)
    ),
    // Observed on a live backend: trailing period after the id.
    (
      "2018-11-02 McMillan Quarterly Statement.pdf: Not consuming 2018-11-02 McMillan Quarterly Statement.pdf: It is a duplicate of Quarterly Statement (#1).",
      UInt(1)
    ),
  ])
  func testDuplicateParsing(result: String, expected: UInt) throws {
    #expect(parseDuplicateDocumentId(from: result) == expected)
  }

  @Test(
    arguments: [
      nil,
      "Success. New document id 29 created",
      "Document processing failed: invalid file format",
    ] as [String?])
  func testDuplicateParsingNoMatch(result: String?) throws {
    #expect(parseDuplicateDocumentId(from: result) == nil)
  }
}
