import DataModel
import Foundation

struct ApiTask: Codable, Sendable {
  var id: UInt
  var task_id: UUID
  var task_file_name: String?
  var task_name: String?
  var date_created: Date?
  var date_done: Date?
  var type: String
  var status: String
  var result: String?
  var acknowledged: Bool
  var related_document: String?
}

extension ApiTask {
  var domain: PaperlessTask {
    PaperlessTask(
      id: id,
      taskId: task_id,
      taskFileName: task_file_name,
      taskName: task_name,
      dateCreated: date_created,
      dateDone: date_done,
      type: type,
      status: TaskStatus(rawValue: status) ?? .UNKNOWN,
      result: result,
      acknowledged: acknowledged,
      relatedDocument: related_document
    )
  }
}
