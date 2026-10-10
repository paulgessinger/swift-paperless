import Foundation
import Persistence
import Testing

@testable import AppShared

@MainActor
@Suite
struct AppStackTests {
  @Test("The connection manager reads the servers from the stack's database")
  func connectionManagerSharesDatabase() throws {
    let serverID = UUID()
    let stack = AppStack(database: try Database.seeded(serverID: serverID))

    #expect(stack.connectionManager.connections.keys.contains(serverID))
  }

  @Test("The registry hands out one session per server")
  func oneSessionPerServer() throws {
    let serverID = UUID()
    let stack = AppStack(database: try Database.seeded(serverID: serverID))

    let first = stack.sessionRegistry.session(for: serverID)
    #expect(stack.sessionRegistry.session(for: serverID) === first)
    #expect(stack.sessionRegistry.session(for: UUID()) !== first)
  }

  @Test("The registry reports a removed server, for the files that live outside the database")
  func serverRemovalIsReported() async throws {
    let serverID = UUID()
    let stack = AppStack(database: try Database.seeded(serverID: serverID))
    var removed: Set<UUID> = []
    stack.sessionRegistry.onServersRemoved = { removed = $0 }
    stack.sessionRegistry.start()

    _ = try stack.database.deleteConnection(id: serverID)

    try await waitUntil({ removed == [serverID] }, "the removal was never reported")
  }

  @Test("Without a content store the stack caches no files and the reclaim is harmless")
  func noStoreNoFiles() async throws {
    let stack = AppStack(database: try Database.seeded())

    #expect(stack.sessionRegistry.contentReclaimer?.store == nil)
    let report = await stack.contentReclaimer.run(reason: .manual)
    #expect(report.removedFiles == 0)
    #expect(!report.walked)
  }
}
