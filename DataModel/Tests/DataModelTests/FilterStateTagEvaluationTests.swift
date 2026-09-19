//
//  FilterStateTagEvaluationTests.swift
//  DataModel
//

import Foundation
import Testing

@testable import DataModel

private func filter(_ tags: FilterState.TagFilter, remaining: [FilterRule] = []) -> FilterState {
  FilterState.empty.with {
    $0.tags = tags
    $0.remaining = remaining
  }
}

private func rule(_ type: FilterRuleType, _ value: FilterRuleValue) -> FilterRule {
  FilterRule(ruleType: type, value: value)!
}

@Suite("FilterState tag evaluation", .bug(id: "676"))
struct FilterStateTagEvaluationTests {
  @Test("No tag condition never excludes")
  func anyTags() {
    let state = filter(.any)
    #expect(!state.tagRulesExclude(tags: []))
    #expect(!state.tagRulesExclude(tags: [1, 2, 3]))
  }

  @Test("Not assigned: only untagged documents pass")
  func notAssigned() {
    let state = filter(.notAssigned)
    #expect(!state.tagRulesExclude(tags: []))
    #expect(state.tagRulesExclude(tags: [1]))
  }

  @Test("Any of: at least one listed tag")
  func anyOf() {
    let state = filter(.anyOf(ids: [1, 2]))
    #expect(!state.tagRulesExclude(tags: [1]))
    #expect(!state.tagRulesExclude(tags: [2, 9]))
    #expect(state.tagRulesExclude(tags: [9]))
    #expect(state.tagRulesExclude(tags: []))
  }

  @Test("All of: every included tag, none of the excluded ones")
  func allOf() {
    let state = filter(.allOf(include: [1, 2], exclude: [3]))
    #expect(!state.tagRulesExclude(tags: [1, 2]))
    #expect(!state.tagRulesExclude(tags: [1, 2, 4]))
    #expect(state.tagRulesExclude(tags: [1]))
    #expect(state.tagRulesExclude(tags: [1, 2, 3]))
    #expect(state.tagRulesExclude(tags: []))
  }

  @Test("Exclude-only: anything without the excluded tags passes")
  func excludeOnly() {
    let state = filter(.allOf(include: [], exclude: [3, 4]))
    #expect(!state.tagRulesExclude(tags: []))
    #expect(!state.tagRulesExclude(tags: [1]))
    #expect(state.tagRulesExclude(tags: [4]))
  }

  @Test("Tag rules left in `remaining` are evaluated too")
  func remainingRules() {
    // An "any of" next to an "all of" can't be represented in `tags`, so it is
    // carried in `remaining` — but it is still sent, and still narrows.
    let state = filter(
      .allOf(include: [1], exclude: []),
      remaining: [rule(.hasTagsAny, .tag(id: 5)), rule(.hasTagsAny, .tag(id: 6))])
    #expect(!state.tagRulesExclude(tags: [1, 5]))
    #expect(!state.tagRulesExclude(tags: [1, 6]))
    #expect(state.tagRulesExclude(tags: [1]))
    #expect(state.tagRulesExclude(tags: [5]))
  }

  @Test("is_tagged=true in remaining requires at least one tag")
  func isTaggedTrue() {
    let state = filter(.any, remaining: [rule(.hasAnyTag, .boolean(value: true))])
    #expect(state.tagRulesExclude(tags: []))
    #expect(!state.tagRulesExclude(tags: [7]))
  }

  @Test("Rules populated from a saved view evaluate the same")
  func populatedFromRules() {
    let state = FilterState.create(
      using: \.empty,
      withRules: [
        rule(.hasTagsAll, .tag(id: 1)),
        rule(.hasTagsAll, .tag(id: 2)),
        rule(.doesNotHaveTag, .tag(id: 3)),
      ])
    #expect(state.tags == .allOf(include: [1, 2], exclude: [3]))
    #expect(!state.tagRulesExclude(tags: [1, 2]))
    #expect(state.tagRulesExclude(tags: [2]))
  }

  @Test("is_in_inbox is never evaluated")
  func isInInbox() {
    // The server only honours the literal `true`/`false` here, and deciding
    // it would need to know the inbox tags; neither is available.
    let state = filter(.any, remaining: [rule(.isInInbox, .boolean(value: true))])
    #expect(!state.tagRulesExclude(tags: []))
    #expect(!state.tagChangeExcludes(from: [1], to: []))
  }

  @Test("A tag parameter sent twice is undecidable, so never excludes")
  func duplicateParameter() {
    // `is_tagged=1` from `remaining` and `is_tagged=0` from `.notAssigned`:
    // whichever the server reads wins, and that is not ours to guess.
    let state = filter(.notAssigned, remaining: [rule(.hasAnyTag, .boolean(value: true))])
    #expect(!state.tagRulesExclude(tags: []))
    #expect(!state.tagRulesExclude(tags: [1]))
  }

  @Test("A value the server can't parse leaves the parameter unapplied")
  func unparsableValue() {
    let state = filter(.any, remaining: [rule(.hasTagsAll, .invalid(value: "1,x"))])
    #expect(!state.tagRulesExclude(tags: []))
  }

  @Test("Non-tag rules don't affect the verdict")
  func otherRules() {
    let state = filter(.anyOf(ids: [1])).with {
      $0.correspondent = .anyOf(ids: [4])
      $0.searchText = "invoice"
    }
    #expect(!state.tagRulesExclude(tags: [1]))
    #expect(state.tagRulesExclude(tags: [2]))
  }

  @Test("Removing the inbox tag takes a document out of an inbox view")
  func inboxTriage() {
    let inbox: UInt = 1
    let state = filter(.anyOf(ids: [inbox]))
    #expect(state.tagChangeExcludes(from: [inbox, 5], to: [5]))
    // Still matches: nothing to remove.
    #expect(!state.tagChangeExcludes(from: [inbox, 5], to: [inbox]))
  }

  @Test("A document already rejected before the change is left alone")
  func alreadyExcluded() {
    let state = filter(.anyOf(ids: [1]))
    #expect(!state.tagChangeExcludes(from: [2], to: [3]))
  }

  @Test("Adding an excluded tag takes a document out")
  func addingExcludedTag() {
    let state = filter(.allOf(include: [], exclude: [9]))
    #expect(state.tagChangeExcludes(from: [1], to: [1, 9]))
  }
}
