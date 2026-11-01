import DataModel
import Foundation

// Matches Paperless-ngx duplicate failure messages of the form:
//   "<file>: Not consuming <file>: It is a duplicate of <other> (#<id>)"
// A trailing period after the closing paren has been observed in the wild.
func parseDuplicateDocumentId(from result: String?) -> UInt? {
  let pattern = /(.*): Not consuming (.*): It is a duplicate of (.*) \(#(\d+)\)\.?/
  guard let result, let match = try? pattern.wholeMatch(in: result) else {
    return nil
  }
  return UInt(match.4)
}

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
      relatedDocument: related_document,
      duplicateDocumentId: parseDuplicateDocumentId(from: result)
    )
  }
}

struct ApiTaskV10: Codable, Sendable {
  struct InputData: Codable, Sendable {
    var filename: String?
  }

  // `result_data` is a free-form JSON object whose keys depend on the task, so
  // a key of an unexpected type is treated as absent rather than failing the
  // whole task list.
  struct ResultData: Codable, Sendable {
    var document_id: UInt?
    var reason: String?
    var duplicate_of: UInt?
    var error_message: String?

    private enum CodingKeys: String, CodingKey {
      case document_id, reason, duplicate_of, error_message
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      document_id = try? container.decodeIfPresent(UInt.self, forKey: .document_id)
      reason = try? container.decodeIfPresent(String.self, forKey: .reason)
      duplicate_of = try? container.decodeIfPresent(UInt.self, forKey: .duplicate_of)
      error_message = try? container.decodeIfPresent(String.self, forKey: .error_message)
    }
  }

  var id: UInt
  var task_id: UUID
  var task_type: String
  var trigger_source: String
  var status: String
  var date_created: Date?
  var date_done: Date?
  var result_data: ResultData?
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
      // Only the server's own text: a created document or a duplicate has an
      // id instead, and the display layer words those.
      result: result_data?.reason ?? result_data?.error_message,
      acknowledged: acknowledged,
      relatedDocument: related_document_ids.first.map(String.init),
      duplicateDocumentId: result_data?.duplicate_of,
      createdDocumentId: result_data?.document_id
    )
  }
}
