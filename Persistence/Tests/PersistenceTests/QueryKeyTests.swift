import DataModel
import Foundation
import Testing

@testable import Persistence

@Suite("QueryKey")
struct QueryKeyTests {
  private let server = UUID()

  @Test("is deterministic across re-computation (the SHA-vs-Hasher guard)")
  func deterministic() {
    let filter = FilterState.empty
    #expect(
      QueryKey(serverID: server, filter: filter).rawValue
        == QueryKey(serverID: server, filter: filter).rawValue)
  }

  @Test("ignores the transient `modified` flag")
  func ignoresModified() {
    let a = FilterState.empty
    var b = FilterState.empty
    b.modified = true
    #expect(QueryKey(serverID: server, filter: a) == QueryKey(serverID: server, filter: b))
  }

  @Test("changes when the sort order flips")
  func sortOrderMatters() {
    let asc = FilterState.empty.with { $0.sortOrder = .ascending }
    let desc = FilterState.empty.with { $0.sortOrder = .descending }
    #expect(QueryKey(serverID: server, filter: asc) != QueryKey(serverID: server, filter: desc))
  }

  @Test("changes when the sort field changes")
  func sortFieldMatters() {
    let byAsn = FilterState.empty.with { $0.sortField = .asn }
    let byTitle = FilterState.empty.with { $0.sortField = .title }
    #expect(
      QueryKey(serverID: server, filter: byAsn) != QueryKey(serverID: server, filter: byTitle))
  }

  @Test("changes when a filter rule changes")
  func filterRulesMatter() {
    let one = FilterState.empty.with { $0.correspondent = .anyOf(ids: [1]) }
    let two = FilterState.empty.with { $0.correspondent = .anyOf(ids: [2]) }
    #expect(QueryKey(serverID: server, filter: one) != QueryKey(serverID: server, filter: two))
  }

  @Test("is independent of the order ids were added to a multi-value filter")
  func idOrderStable() {
    let a = FilterState.empty.with { $0.correspondent = .anyOf(ids: [1, 2, 3]) }
    let b = FilterState.empty.with { $0.correspondent = .anyOf(ids: [3, 1, 2]) }
    #expect(QueryKey(serverID: server, filter: a) == QueryKey(serverID: server, filter: b))
  }

  @Test("is scoped to the server")
  func serverScoped() {
    let filter = FilterState.empty
    #expect(
      QueryKey(serverID: UUID(), filter: filter) != QueryKey(serverID: UUID(), filter: filter))
  }

  @Test("a sentinel key is its literal string")
  func sentinel() {
    #expect(QueryKey(sentinel: "local:downloaded").rawValue == "local:downloaded")
  }
}
