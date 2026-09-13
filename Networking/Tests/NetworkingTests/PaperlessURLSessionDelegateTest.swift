//
//  PaperlessURLSessionDelegateTest.swift
//  Networking
//
//  Foundation's `urlSession(_:task:didFinishCollecting:)` can't be driven from a
//  test (`URLSessionTaskMetrics` has no usable initializer), so these cover
//  everything past the metrics summation: the `record(sent:received:)` seam.
//

import Foundation
import Testing

@testable import Networking

@Suite("PaperlessURLSessionDelegate transfer recording")
struct PaperlessURLSessionDelegateTest {
  private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(Int64, Int64)] = []
    func record(_ sent: Int64, _ received: Int64) {
      lock.withLock { entries.append((sent, received)) }
    }

    var sent: [Int64] { lock.withLock { entries.map(\.0) } }
    var received: [Int64] { lock.withLock { entries.map(\.1) } }
  }

  @Test("a recording delegate reports sent and received bytes unchanged")
  func recordingDelegateForwards() {
    let recorder = Recorder()
    let delegate = PaperlessURLSessionDelegate(identity: nil)
      .recordingTransfers { sent, received in recorder.record(sent, received) }

    delegate.record(sent: 120, received: 4096)
    delegate.record(sent: 80, received: 0)

    #expect(recorder.sent == [120, 80])
    #expect(recorder.received == [4096, 0])
  }

  @Test("the base delegate records nothing and derivation leaves it that way")
  func baseDelegateIsSilent() {
    let recorder = Recorder()
    let base = PaperlessURLSessionDelegate(identityName: nil)
    let recording = base.recordingTransfers { sent, received in recorder.record(sent, received) }

    base.record(sent: 1, received: 1)
    #expect(recorder.sent.isEmpty)

    recording.record(sent: 2, received: 3)
    #expect(recorder.sent == [2])
    #expect(base !== recording)
  }
}
