//
//  TaskModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.07.23.
//

import Foundation

enum TaskStatus: String, Codable {
    case PENDING
    case STARTED
    case SUCCESS
    case FAILURE
    case RETRY
    case REVOKED
}

enum TaskType: String, Codable {
    case file
}

struct PaperlessTask: Model, Codable, Equatable, Hashable, Identifiable {
    static var localizedName: String { "FileTask" }

    var id: UInt
    var taskId: UUID
    var taskFileName: String?
    var taskName: String?
    var dateCreated: Date?
    var dateDone: Date?
    var type: TaskType
    var status: TaskStatus
    var result: String?
    var acknowledged: Bool
    var relatedDocument: String?

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

    var isActive: Bool {
        switch status {
        case .PENDING, .STARTED, .RETRY:
            return true
        default:
            return false
        }
    }
}
