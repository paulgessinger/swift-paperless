//
//  TaskModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.07.23.
//

import Foundation
import MetaCodable

public enum TaskStatus: String, Codable, Sendable {
    case PENDING
    case STARTED
    case SUCCESS
    case FAILURE
    case RETRY
    case REVOKED
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
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

    public var isActive: Bool {
        switch status {
        case .PENDING, .STARTED, .RETRY:
            true
        default:
            false
        }
    }
}
