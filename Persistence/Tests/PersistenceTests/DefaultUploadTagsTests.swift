import Foundation
import Testing

@testable import Persistence

@Suite("Default upload tags")
struct DefaultUploadTagsTests {
  private let server = UUID()
  private let other = UUID()

  private func makeDatabase() throws -> Persistence.Database {
    let database = try Persistence.Database.seeded(serverID: server)
    try database.upsertConnection(
      ConnectionRecord(
        id: other, url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: false, username: "alice")))
    return database
  }

  @Test("Setting replaces a server's tags and leaves other servers alone")
  func setReplacesPerServer() async throws {
    let database = try makeDatabase()
    try await database.setDefaultUploadTags([7, 3], serverID: other)

    try await database.setDefaultUploadTags([7, 3, 7], serverID: server)
    try await database.setDefaultUploadTags([12, 3], serverID: server)

    #expect(try await database.defaultUploadTags(serverID: server) == [3, 12])
    #expect(try await database.defaultUploadTags(serverID: other) == [3, 7])
  }

  @Test("The tags are configuration: a cache wipe keeps them, removing the server drops them")
  func survivesWipeNotServerRemoval() async throws {
    let database = try makeDatabase()
    try await database.setDefaultUploadTags([7], serverID: server)

    try await database.clearCache()
    #expect(try await database.defaultUploadTags(serverID: server) == [7])

    try database.deleteConnection(id: server)
    #expect(try await database.defaultUploadTags(serverID: server).isEmpty)
  }
}
