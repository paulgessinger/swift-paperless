import DataModel
import Foundation
import Testing

@testable import Networking

@Suite("ApiDocumentNote")
struct ApiDocumentNoteTest {
  @Test("Decodes user as struct, int, or null")
  func testDecodeUserVariants() throws {
    let jsonWithUserStruct = """
      {
          "id": 1,
          "note": "Test note",
          "created": "2023-09-05T12:00:00Z",
          "user": { "id": 42, "username": "alice" }
      }
      """
    let jsonWithUserInt = """
      {
          "id": 2,
          "note": "Test note 2",
          "created": "2023-09-05T12:00:00Z",
          "user": 99
      }
      """
    let jsonWithUserNull = """
      {
          "id": 3,
          "note": "Test note 3",
          "created": "2023-09-05T12:00:00Z",
          "user": null
      }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let note1 = try decoder.decode(ApiDocumentNote.self, from: Data(jsonWithUserStruct.utf8)).domain
    #expect(note1.user == DocumentNote.User(id: 42, username: "alice"))

    let note2 = try decoder.decode(ApiDocumentNote.self, from: Data(jsonWithUserInt.utf8)).domain
    #expect(note2.user == DocumentNote.User(id: 99, username: ""))

    let note3 = try decoder.decode(ApiDocumentNote.self, from: Data(jsonWithUserNull.utf8)).domain
    #expect(note3.user == nil)
  }
}
