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
}
