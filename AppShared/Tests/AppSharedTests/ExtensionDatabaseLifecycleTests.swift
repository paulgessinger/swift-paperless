import Foundation
import Persistence
import Testing
import os

@testable import AppShared

/// What the extension's lifecycle tells the controller, against recorded calls
/// rather than a real database.
@MainActor
@Suite("Extension database lifecycle")
struct ExtensionDatabaseLifecycleTests {
  enum Call: Equatable {
    case suspend
    case resume
    case requestTime
    case releaseTime
  }

  final class Recorder {
    var calls: [Call] = []
  }

  private func makeLifecycle() -> (
    ExtensionDatabaseLifecycle, DatabaseSuspensionController, Recorder
  ) {
    let recorder = Recorder()
    let controller = DatabaseSuspensionController(
      suspend: { recorder.calls.append(.suspend) },
      resume: { recorder.calls.append(.resume) },
      requestTime: { _ in
        recorder.calls.append(.requestTime)
        return { recorder.calls.append(.releaseTime) }
      })
    let lifecycle = ExtensionDatabaseLifecycle(suspension: controller)
    lifecycle.willAppear()
    recorder.calls = []
    return (lifecycle, controller, recorder)
  }

  @Test("Dismissing with no work suspends, once however many signals report it")
  func dismissWithoutWork() {
    let (lifecycle, _, recorder) = makeLifecycle()
    lifecycle.didDisappear()
    lifecycle.didDisappear()
    lifecycle.hostDidEnterBackground()
    #expect(recorder.calls == [.suspend])
  }

  @Test("Dismissing during work keeps the writer open on granted time until the work ends")
  func dismissDuringWork() {
    let (lifecycle, controller, recorder) = makeLifecycle()
    controller.beginBackgroundWork()
    lifecycle.didDisappear()
    #expect(recorder.calls == [.requestTime])
    controller.endBackgroundWork()
    #expect(recorder.calls == [.requestTime, .suspend, .releaseTime])
  }

  @Test("Work starting after the dismissal opens the writer for itself")
  func workAfterDismiss() {
    let (lifecycle, controller, recorder) = makeLifecycle()
    lifecycle.didDisappear()
    controller.beginBackgroundWork()
    controller.endBackgroundWork()
    #expect(recorder.calls == [.suspend, .resume, .requestTime, .suspend, .releaseTime])
  }

  @Test("The host leaving and coming back suspends and resumes")
  func hostLifecycle() {
    let (lifecycle, _, recorder) = makeLifecycle()
    lifecycle.hostDidEnterBackground()
    lifecycle.hostWillEnterForeground()
    #expect(recorder.calls == [.suspend, .resume])
  }

  @Test("The host returning after the dismissal leaves the writer suspended")
  func hostReturnsAfterDismiss() {
    let (lifecycle, _, recorder) = makeLifecycle()
    lifecycle.didDisappear()
    lifecycle.hostDidEnterBackground()
    lifecycle.hostWillEnterForeground()
    #expect(recorder.calls == [.suspend])
  }

  @Test("A new request in a reused process resumes, even if the host's return was missed")
  func reusedProcess() {
    let (lifecycle, _, recorder) = makeLifecycle()
    lifecycle.hostDidEnterBackground()
    lifecycle.didDisappear()
    lifecycle.willAppear()
    #expect(recorder.calls == [.suspend, .resume])
  }
}

/// The grant against a stand-in for `performExpiringActivity`, calling back on
/// a concurrent queue as the real one does.
@MainActor
@Suite("Expiring activity time")
struct ExpiringActivityTimeTests {
  /// Captures the activity's block in place of running it.
  final class FakeActivity: Sendable {
    private let state = OSAllocatedUnfairLock<(@Sendable (Bool) -> Void)?>(initialState: nil)

    var activity: ExpiringActivityTime.Activity {
      { [state] block in state.withLock { $0 = block } }
    }

    /// Calls the block off the main actor and returns once it has returned.
    func call(expired: Bool) async {
      let block = state.withLock { $0 }
      await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
          block?(expired)
          continuation.resume()
        }
      }
    }
  }

  final class Counter {
    var value = 0
  }

  @Test("Releasing ends the activity without reporting expiry")
  func release() async throws {
    let fake = FakeActivity()
    let expired = Counter()
    let release = ExpiringActivityTime.request(activity: fake.activity) { expired.value += 1 }

    let running = Task { await fake.call(expired: false) }
    try await Task.sleep(for: .milliseconds(20))
    release()
    await running.value
    #expect(expired.value == 0)
  }

  @Test("Releasing before the block starts lets it return at once")
  func releaseBeforeStart() async {
    let fake = FakeActivity()
    let release = ExpiringActivityTime.request(activity: fake.activity) {}
    release()
    await fake.call(expired: false)
  }

  @Test("Expiry reports once and ends the running activity")
  func expiryEndsActivity() async {
    let fake = FakeActivity()
    let expired = Counter()
    let release = ExpiringActivityTime.request(activity: fake.activity) { expired.value += 1 }

    let running = Task { await fake.call(expired: false) }
    await fake.call(expired: true)
    await running.value
    #expect(expired.value == 1)

    release()
    #expect(expired.value == 1)
  }

  @Test("No time at all reports expiry from the first call")
  func noTime() async {
    let fake = FakeActivity()
    let expired = Counter()
    _ = ExpiringActivityTime.request(activity: fake.activity) { expired.value += 1 }

    await fake.call(expired: true)
    #expect(expired.value == 1)
  }

  @Test("An expiry arriving after the release is ignored")
  func lateExpiry() async {
    let fake = FakeActivity()
    let expired = Counter()
    let release = ExpiringActivityTime.request(activity: fake.activity) { expired.value += 1 }

    release()
    await fake.call(expired: true)
    #expect(expired.value == 0)
  }

  @Test("The writer is suspended before the expired call returns, with work still running")
  func expirySuspendsController() async {
    let fake = FakeActivity()
    let suspended = Counter()
    let activity = fake.activity
    let controller = DatabaseSuspensionController(
      isInBackground: true,
      suspend: { suspended.value += 1 },
      resume: {},
      requestTime: { ExpiringActivityTime.request(activity: activity, onExpire: $0) })

    controller.beginBackgroundWork()
    await fake.call(expired: true)
    #expect(suspended.value == 1)
    controller.endBackgroundWork()
  }
}
