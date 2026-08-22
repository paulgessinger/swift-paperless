//
//  SyncConditionTests.swift
//  DataModel
//

import Testing

@testable import DataModel

@Suite
struct SyncConditionTests {
  @Test("An unmetered link always allows proactive sync, opt-in or not")
  func unmeteredAlwaysAllowed() {
    #expect(
      SyncCondition(isExpensive: false, isConstrained: false, syncOverCellular: false)
        .allowsProactiveSync)
    #expect(
      SyncCondition(isExpensive: false, isConstrained: false, syncOverCellular: true)
        .allowsProactiveSync)
  }

  @Test("An expensive link requires the opt-in")
  func expensiveRequiresOptIn() {
    #expect(
      !SyncCondition(isExpensive: true, isConstrained: false, syncOverCellular: false)
        .allowsProactiveSync)
    #expect(
      SyncCondition(isExpensive: true, isConstrained: false, syncOverCellular: true)
        .allowsProactiveSync)
  }

  @Test("Low Data Mode always wins, regardless of the opt-in or link cost")
  func constrainedAlwaysWins() {
    #expect(
      !SyncCondition(isExpensive: false, isConstrained: true, syncOverCellular: true)
        .allowsProactiveSync)
    #expect(
      !SyncCondition(isExpensive: true, isConstrained: true, syncOverCellular: true)
        .allowsProactiveSync)
  }
}
