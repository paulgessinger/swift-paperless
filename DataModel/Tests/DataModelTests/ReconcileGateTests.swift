//
//  ReconcileGateTests.swift
//  DataModel
//

import Foundation
import Testing

@testable import DataModel

@Suite
struct ReconcileGateTests {
  private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

  @Test("The first request starts a pass and stamps it")
  func firstStarts() {
    var gate = ReconcileGate(interval: 300)
    let started = gate.start(force: false, now: t0)
    #expect(started)
    #expect(gate.lastStart == t0)
  }

  @Test("An unforced request within the interval is declined and stamps nothing")
  func throttled() {
    var gate = ReconcileGate(interval: 300)
    _ = gate.start(force: false, now: t0)
    let early = gate.start(force: false, now: t0.addingTimeInterval(299))
    #expect(!early)
    #expect(gate.lastStart == t0)
    let afterInterval = gate.start(force: false, now: t0.addingTimeInterval(300))
    #expect(afterInterval)
  }

  @Test("A forced request starts within the interval")
  func forced() {
    var gate = ReconcileGate(interval: 300)
    _ = gate.start(force: false, now: t0)
    let later = t0.addingTimeInterval(10)
    let started = gate.start(force: true, now: later)
    #expect(started)
    #expect(gate.lastStart == later)
  }

  @Test(
    "An owed heal starts the next pass within the interval, once",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/777", id: 777))
  func healBypassesThrottleOnce() {
    var gate = ReconcileGate(interval: 300)
    _ = gate.start(force: false, now: t0)
    gate.oweHeal()
    #expect(gate.isHealOwed)
    let started = gate.start(force: false, now: t0.addingTimeInterval(10))
    #expect(started)
    #expect(!gate.isHealOwed)
    let startedAgain = gate.start(force: false, now: t0.addingTimeInterval(20))
    #expect(!startedAgain)
  }

  @Test(
    "Any pass that starts settles an owed heal",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/777", id: 777))
  func forcedPassSettlesHeal() {
    var gate = ReconcileGate(interval: 300)
    gate.oweHeal()
    let started = gate.start(force: true, now: t0)
    #expect(started)
    #expect(!gate.isHealOwed)
  }
}
