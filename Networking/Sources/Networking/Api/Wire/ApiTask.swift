import DataModel
import Foundation

struct ApiTaskV9: Codable, Sendable {
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

extension ApiTaskV9 {
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

struct ApiTaskV10: Codable, Sendable {
  struct InputData: Codable, Sendable {
    var filename: String?
  }

  var id: UInt
  var task_id: UUID
  var task_type: String
  var trigger_source: String
  var status: String
  var date_created: Date?
  var date_done: Date?
  var result_message: String?
  var input_data: InputData?
  var related_document_ids: [UInt]
  var acknowledged: Bool
}

extension ApiTaskV10 {
  var domain: PaperlessTask {
    // v10 sends lowercase status strings; TaskStatus raw values are uppercase.
    let normalizedStatus = TaskStatus(rawValue: status.uppercased()) ?? .UNKNOWN
    return PaperlessTask(
      id: id,
      taskId: task_id,
      taskFileName: input_data?.filename,
      taskName: task_type,
      dateCreated: date_created,
      dateDone: date_done,
      type: trigger_source,
      status: normalizedStatus,
      result: result_message,
      acknowledged: acknowledged,
      relatedDocument: related_document_ids.first.map(String.init)
    )
  }
}
