import DataModel
import Foundation
import Networking
import Persistence
import Testing

@testable import AppShared

@Suite("ConnectionManager default upload tags")
@MainActor
struct ConnectionManagerDefaultUploadTagsTests {
  private static func stored() -> StoredConnection {
    StoredConnection(
      url: URL(string: "https://example.com/api/")!,
      extraHeaders: [],
      user: User(id: 1, isSuperUser: false, username: "a"))
  }

  @Test("tags are set on the given server, not the active one")
  func setsTagsOnGivenServer() throws {
    let database = try Database.inMemory()
    let manager = ConnectionManager(database: database, previewMode: false)
    let first = Self.stored()
    let second = Self.stored()
    try manager.login(first)
    try manager.login(second)
    #expect(manager.activeConnectionId == second.id)

    manager.setDefaultUploadTags([7, 3], for: first.id)

    #expect(manager.connections[first.id]?.defaultUploadTags == [7, 3])
    #expect(manager.connections[second.id]?.defaultUploadTags == [])
    #expect(try database.connection(id: first.id)?.defaultUploadTags == [7, 3])
    #expect(try database.connection(id: second.id)?.defaultUploadTags == [])
  }

  @Test("tags on an unknown server are ignored")
  func ignoresUnknownServer() throws {
    let database = try Database.inMemory()
    let manager = ConnectionManager(database: database, previewMode: false)

    manager.setDefaultUploadTags([7], for: UUID())

    #expect(manager.connections.isEmpty)
    #expect(try database.allConnections().isEmpty)
  }

  @Test("removing a server removes its tags with it")
  func logoutRemovesTags() throws {
    let database = try Database.inMemory()
    let manager = ConnectionManager(database: database, previewMode: false)
    let server = Self.stored()
    try manager.login(server)
    manager.setDefaultUploadTags([7], for: server.id)

    manager.logout(animated: false)

    #expect(try database.connection(id: server.id) == nil)
  }
}
