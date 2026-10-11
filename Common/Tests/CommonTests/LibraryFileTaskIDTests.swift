import Foundation
import Testing

@testable import Common

@Suite
struct LibraryFileTaskIDTests {
  @Test("The id carries the key, the document and the modified, and parses back")
  func roundTrip() throws {
    let key = ContentStore.Key(serverID: UUID(), versionID: 91, kind: .archive)
    let modified = Date(timeIntervalSinceReferenceDate: 1234.5)

    let parsed = try #require(
      LibraryFileTaskID.parse(LibraryFileTaskID.make(key: key, documentID: 7, modified: modified)))
    #expect(parsed.key == key)
    #expect(parsed.documentID == 7)
    #expect(parsed.modified == modified)
  }

  @Test("Anything else is rejected")
  func rejectsOthers() {
    let id = LibraryFileTaskID.make(
      key: ContentStore.Key(serverID: UUID(), versionID: 1, kind: .archive), documentID: 1,
      modified: Date())
    #expect(LibraryFileTaskID.parse(id + "/x") == nil)
    #expect(LibraryFileTaskID.parse("swift-paperless:thumbnail/x") == nil)
    #expect(LibraryFileTaskID.parse("swift-paperless:file/not-a-uuid/1/1/archive/0") == nil)
    #expect(
      LibraryFileTaskID.parse("swift-paperless:file/\(UUID().uuidString)/1/1/video/0") == nil)
  }
}
