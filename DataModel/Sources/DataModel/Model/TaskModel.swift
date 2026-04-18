//
//  TaskModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.07.23.
//

import Foundation

public enum TaskStatus: String, Sendable {
  case PENDING
  case STARTED
  case SUCCESS
  case FAILURE
  case RETRY
  case REVOKED
  case UNKNOWN
}

// See https://github.com/paperless-ngx/paperless-ngx/blob/4c6fdbb21fdcd3ecf81b9a0dd87487f146066e01/src/documents/models.py#L542C9-L545C65
public enum TaskName: String, Sendable {
  // There might be more added but this is not (currently) used for deserialization
  case consumeFile = "consume_file"
  case trainClassifier = "train_classifier"
  case checkSanity = "check_sanity"
  case indexOptimize = "index_optimize"
}

public struct PaperlessTask: Model, Identifiable, Hashable, Sendable {
  public var id: UInt
  public var taskId: UUID
  public var taskFileName: String?
  public var taskName: String?
  public var dateCreated: Date?
  public var dateDone: Date?
  public var type: String
  public var status: TaskStatus
  public var result: String?
  public var acknowledged: Bool
  public var relatedDocument: String?

  public init(
    id: UInt,
    taskId: UUID,
    taskFileName: String? = nil,
    taskName: String? = nil,
    dateCreated: Date? = nil,
    dateDone: Date? = nil,
    type: String,
    status: TaskStatus,
    result: String? = nil,
    acknowledged: Bool,
    relatedDocument: String? = nil
  ) {
    self.id = id
    self.taskId = taskId
    self.taskFileName = taskFileName
    self.taskName = taskName
    self.dateCreated = dateCreated
    self.dateDone = dateDone
    self.type = type
    self.status = status
    self.result = result
    self.acknowledged = acknowledged
    self.relatedDocument = relatedDocument
  }

  public var isActive: Bool {
    switch status {
    case .PENDING, .STARTED, .RETRY:
      true
    case .SUCCESS, .FAILURE, .REVOKED, .UNKNOWN:
      false
    }
  }
}
