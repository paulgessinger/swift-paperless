
import DataModel
import Foundation
import Testing

@Suite("DocumentNote")
struct DocumentNoteTests {
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

        let note1 = try decoder.decode(DocumentNote.self, from: Data(jsonWithUserStruct.utf8))
        #expect(note1.user == DocumentNote.User(id: 42, username: "alice"))

        let note2 = try decoder.decode(DocumentNote.self, from: Data(jsonWithUserInt.utf8))
        #expect(note2.user == DocumentNote.User(id: 99, username: ""))

        let note3 = try decoder.decode(DocumentNote.self, from: Data(jsonWithUserNull.utf8))
        #expect(note3.user == nil)
    }
}
