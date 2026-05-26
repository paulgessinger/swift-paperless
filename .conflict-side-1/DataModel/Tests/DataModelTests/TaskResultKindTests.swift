//
//  TaskResultKindTests.swift
//  DataModelTests
//
//  Covers PaperlessTask.resultKind — the parse/branch decision used by the
//  AppShared localization layer to format a user-facing message.
//

import Foundation
import Testing

@testable import DataModel

@Suite("ResultKind")
struct PaperlessTaskResultKindTests {
  @Test
  func duplicateClassification() throws {
    let task = PaperlessTask(
      id: 1, taskId: .init(),
      taskFileName: "2015-02-01 Car Garage Health Employee Data Collection Form.pdf",
      type: "file", status: .FAILURE,
      result:
        "2015-02-01 Car Garage Health Employee Data Collection Form.pdf: Not consuming 2015-02-01 Car Garage Health Employee Data Collection Form.pdf: It is a duplicate of 2015-02-01 Car Garage Health Employee Data Collection Form.pdf (#28)",
      acknowledged: false,
      duplicateDocumentId: 28)

    #expect(task.resultKind == .duplicate(fileName: task.taskFileName))
  }

  @Test
  func emptyWhenResultIsNil() throws {
    let task = PaperlessTask(
      id: 1, taskId: .init(),
      type: "file", status: .SUCCESS,
      result: nil,
      acknowledged: false)

    #expect(task.resultKind == .empty)
  }

  @Test
  func rawWhenNoDuplicateId() throws {
    let task = PaperlessTask(
      id: 1, taskId: .init(),
      type: "file", status: .FAILURE,
      result: "Some unrelated failure",
      acknowledged: false)

    #expect(task.resultKind == .raw("Some unrelated failure"))
  }
}
