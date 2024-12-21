//
//  TaskModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.07.23.
//

import Foundation

public enum TaskStatus: String, Codable, Sendable {
    case PENDING
    case STARTED
    case SUCCESS
    case FAILURE
    case RETRY
    case REVOKED
}

public enum TaskType: String, Codable, Sendable {
    case file
}

public struct PaperlessTask:
    Model, Codable, Equatable, Hashable, Identifiable, Sendable
{
    public var id: UInt
    public var taskId: UUID
    public var taskFileName: String?
    public var taskName: String?
    public var dateCreated: Date?
    public var dateDone: Date?
    public var type: TaskType
    public var status: TaskStatus
    public var result: String?
    public var acknowledged: Bool
    public var relatedDocument: String?

    public init(id: UInt, taskId: UUID, taskFileName: String? = nil, taskName: String? = nil, dateCreated: Date? = nil, dateDone: Date? = nil, type: TaskType, status: TaskStatus, result: String? = nil, acknowledged: Bool, relatedDocument: String? = nil) {
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

    private enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case taskFileName = "task_file_name"
        case taskName = "task_name"
        case dateCreated = "date_created"
        case dateDone = "date_done"
        case type, status, result, acknowledged
        case relatedDocument = "related_document"
    }

    public var isActive: Bool {
        switch status {
        case .PENDING, .STARTED, .RETRY:
            true
        default:
            false
        }
    }
}
