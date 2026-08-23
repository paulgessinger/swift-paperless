//
//  SyncConditionTests.swift
//  DataModel
//

import Testing

@testable import DataModel

@Suite
struct SyncConditionTests {
  @Test("An unmeasurable link is treated as the most restrictive one there is")
  func unknownDeniesProactiveSync() {
    // The fallback used to be an unnamed `(true, true)` tuple at the one call
    // site that had it. Pinned here so the conservative choice is a decision
    // the tests defend, not an accident of how a closure was written.
    #expect(!SyncCondition(cost: .unknown, syncOverCellular: true).allowsProactiveSync)
    #expect(!SyncCondition(cost: .unknown, syncOverCellular: false).allowsProactiveSync)
  }

  @Test("An unmetered link always allows proactive sync, opt-in or not")
  func unmeteredAlwaysAllowed() {
    #expect(
      SyncCondition(
        cost: .unrestricted, syncOverCellular: false
      )
      .allowsProactiveSync)
    #expect(
      SyncCondition(
        cost: .unrestricted, syncOverCellular: true
      )
      .allowsProactiveSync)
  }

  @Test("An expensive link requires the opt-in")
  func expensiveRequiresOptIn() {
    #expect(
      !SyncCondition(
        cost: LinkCost(isExpensive: true, isConstrained: false), syncOverCellular: false
      )
      .allowsProactiveSync)
    #expect(
      SyncCondition(cost: LinkCost(isExpensive: true, isConstrained: false), syncOverCellular: true)
        .allowsProactiveSync)
  }

  @Test("Low Data Mode always wins, regardless of the opt-in or link cost")
  func constrainedAlwaysWins() {
    #expect(
      !SyncCondition(
        cost: LinkCost(isExpensive: false, isConstrained: true), syncOverCellular: true
      )
      .allowsProactiveSync)
    #expect(
      !SyncCondition(cost: LinkCost(isExpensive: true, isConstrained: true), syncOverCellular: true)
        .allowsProactiveSync)
  }
}
