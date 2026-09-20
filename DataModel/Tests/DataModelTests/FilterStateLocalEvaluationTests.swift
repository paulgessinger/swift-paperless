//
//  FilterStateLocalEvaluationTests.swift
//  DataModel
//

import Foundation
import Testing

@testable import DataModel

private func document(tags: [UInt] = [], id: UInt = 1) -> Document {
  Document(
    id: id, title: "Doc", asn: nil, created: Date(timeIntervalSince1970: 1000), tags: tags,
    owner: .user(1))
}

private func filter(
  tags: FilterState.TagFilter = .any, _ factory: (inout FilterState) -> Void = { _ in }
)
  -> FilterState
{
  FilterState.empty.with {
    $0.tags = tags
    factory(&$0)
  }
}

@Suite("FilterState local evaluation", .bug(id: "676"))
struct FilterStateLocalEvaluationTests {
  // MARK: - Tags

  @Test("No tag condition accepts anything")
  func anyTags() {
    #expect(filter().accepts(document()) == true)
    #expect(filter().accepts(document(tags: [1, 2])) == true)
  }

  @Test("Not assigned accepts only untagged documents")
  func notAssigned() {
    let state = filter(tags: .notAssigned)
    #expect(state.accepts(document()) == true)
    #expect(state.accepts(document(tags: [1])) == false)
  }

  @Test("Any of accepts a document sharing at least one tag")
  func anyOf() {
    let state = filter(tags: .anyOf(ids: [1, 2]))
    #expect(state.accepts(document(tags: [1])) == true)
    #expect(state.accepts(document(tags: [2, 9])) == true)
    #expect(state.accepts(document(tags: [9])) == false)
    #expect(state.accepts(document()) == false)
  }

  @Test("An empty selection constrains nothing, as on the server")
  func emptyAnyOf() {
    #expect(filter(tags: .anyOf(ids: [])).accepts(document()) == true)
  }

  @Test("All of requires every included tag and no excluded one")
  func allOf() {
    let state = filter(tags: .allOf(include: [1, 2], exclude: [3]))
    #expect(state.accepts(document(tags: [1, 2])) == true)
    #expect(state.accepts(document(tags: [1, 2, 4])) == true)
    #expect(state.accepts(document(tags: [1])) == false)
    #expect(state.accepts(document(tags: [1, 2, 3])) == false)
    #expect(state.accepts(document()) == false)
  }

  @Test("Exclude-only accepts anything without the excluded tags")
  func excludeOnly() {
    let state = filter(tags: .allOf(include: [], exclude: [3, 4]))
    #expect(state.accepts(document()) == true)
    #expect(state.accepts(document(tags: [1])) == true)
    #expect(state.accepts(document(tags: [4])) == false)
  }

  // MARK: - Unset vs set-but-unimplemented

  @Test("Unset conditions contribute nothing")
  func unsetConditions() {
    // Everything but the tags is at its "no constraint" value, including the
    // parts of a filter that order or label it rather than narrow it.
    let state = filter(tags: .anyOf(ids: [1])) {
      $0.sortField = .title
      $0.sortOrder = .ascending
      $0.savedView = 7
      $0.modified = true
    }
    #expect(state.accepts(document(tags: [1])) == true)
    #expect(state.accepts(document(tags: [2])) == false)
  }

  @Test("A set condition this can't evaluate makes the whole answer undecidable")
  func setButUnimplemented() {
    let cases: [(String, (inout FilterState) -> Void)] = [
      ("correspondent", { $0.correspondent = .anyOf(ids: [1]) }),
      ("documentType", { $0.documentType = .notAssigned }),
      ("storagePath", { $0.storagePath = .anyOf(ids: [2]) }),
      ("owner", { $0.owner = .noneOf(ids: [3]) }),
      ("asn", { $0.asn = .isNotNull }),
      ("absolute date range", { $0.date = .init(created: .between(start: Date(), end: nil)) }),
      ("relative date range", { $0.date = .init(added: .range(.currentYear)) }),
      ("searchText", { $0.searchText = "invoice" }),
      ("customField", { $0.customField = .expr(8, .exists, .string("true")) }),
      (
        "remaining",
        { $0.remaining = [FilterRule(ruleType: .mimeType, value: .string(value: "pdf"))!] }
      ),
    ]
    for (name, apply) in cases {
      let state = filter(tags: .anyOf(ids: [1]), apply)
      // The document passes the tags, so only the unevaluable condition is
      // left to decide — and it can't.
      #expect(state.accepts(document(tags: [1])) == nil, "\(name)")
    }
  }

  @Test("A saved view's is_in_inbox rule lands in `remaining`, so it is undecidable")
  func isInInbox() {
    // The server only honours the literal `true`/`false` here, and this app
    // sends `1`/`0` — evaluating it would need the inbox tags *and* would have
    // to model a parameter the server ignores.
    let state = FilterState.create(
      using: \.empty,
      withRules: [FilterRule(ruleType: .isInInbox, value: .boolean(value: true))!])
    #expect(state.remaining.count == 1)
    #expect(state.accepts(document(tags: [1])) == nil)
  }

  // MARK: - Composition

  @Test("A definite rejection wins over an undecidable condition")
  func rejectionDominates() {
    let state = filter(tags: .anyOf(ids: [1])) {
      $0.searchText = "invoice"
    }
    // The tags decide it: the server can't return a document the tag filter
    // excludes, whatever the search would have done.
    #expect(state.accepts(document(tags: [2])) == false)
    // Without that rejection there is nothing to go on.
    #expect(state.accepts(document(tags: [1])) == nil)
  }

  // MARK: - The gate

  @Test("Removing the inbox tag takes a document out of an inbox view")
  func inboxTriage() {
    let inbox: UInt = 1
    let state = filter(tags: .anyOf(ids: [inbox]))
    #expect(
      state.stopsAccepting(
        previous: document(tags: [inbox, 5]), updated: document(tags: [5])))
  }

  @Test("A document the filter still accepts stays")
  func stillAccepted() {
    let state = filter(tags: .anyOf(ids: [1]))
    #expect(
      !state.stopsAccepting(previous: document(tags: [1, 5]), updated: document(tags: [1])))
  }

  @Test("A document that didn't match before the edit is left alone")
  func wasNotAccepted() {
    // Our model and the server disagreed about this document; the server put
    // it in the list, so it stays there.
    let state = filter(tags: .anyOf(ids: [1]))
    #expect(!state.stopsAccepting(previous: document(tags: [2]), updated: document(tags: [3])))
  }

  @Test("An undecidable filter never removes anything")
  func undecidableGate() {
    let state = filter(tags: .anyOf(ids: [1])) { $0.searchText = "invoice" }
    #expect(
      !state.stopsAccepting(
        previous: document(tags: [1, 5]), updated: document(tags: [5])))
  }

  @Test("Adding an excluded tag takes a document out")
  func addingExcludedTag() {
    let state = filter(tags: .allOf(include: [], exclude: [9]))
    #expect(
      state.stopsAccepting(previous: document(tags: [1]), updated: document(tags: [1, 9])))
  }
}
