import Testing

@testable import Persistence

/// The controller's rule, against recorded calls rather than a real database:
/// what reaches the writer is `DatabaseSuspensionTests`'s concern.
@MainActor
@Suite("Database suspension controller")
struct DatabaseSuspensionControllerTests {
  enum Call: Equatable {
    case suspend
    case resume
    case requestTime
    case releaseTime
  }

  final class Recorder {
    var calls: [Call] = []
    /// The latest grant's expiry, standing in for iOS's expiration handler.
    var expire: (@MainActor @Sendable () -> Void)?
  }

  private func makeController(isInBackground: Bool = false) -> (
    DatabaseSuspensionController, Recorder
  ) {
    let recorder = Recorder()
    let controller = DatabaseSuspensionController(
      isInBackground: isInBackground,
      suspend: { recorder.calls.append(.suspend) },
      resume: { recorder.calls.append(.resume) },
      requestTime: { onExpire in
        recorder.calls.append(.requestTime)
        recorder.expire = onExpire
        return { recorder.calls.append(.releaseTime) }
      })
    return (controller, recorder)
  }

  @Test("Entering the background with no work suspends, and returning resumes")
  func lifecycleWithoutWork() {
    let (controller, recorder) = makeController()
    controller.didEnterBackground()
    controller.willEnterForeground()
    #expect(recorder.calls == [.suspend, .resume])
  }

  @Test("Work in the background opens the writer with time, then suspends before handing it back")
  func workInBackground() {
    let (controller, recorder) = makeController()
    controller.didEnterBackground()
    controller.beginBackgroundWork()
    #expect(recorder.calls == [.suspend, .resume, .requestTime])
    controller.endBackgroundWork()
    #expect(recorder.calls == [.suspend, .resume, .requestTime, .suspend, .releaseTime])
  }

  @Test("Overlapping work shares one grant and keeps the writer open until the last one ends")
  func overlappingWork() {
    let (controller, recorder) = makeController()
    controller.didEnterBackground()
    controller.beginBackgroundWork()
    controller.beginBackgroundWork()
    controller.endBackgroundWork()
    #expect(recorder.calls == [.suspend, .resume, .requestTime])
    controller.endBackgroundWork()
    #expect(recorder.calls == [.suspend, .resume, .requestTime, .suspend, .releaseTime])
  }

  @Test("Coming to the foreground during work hands the time back, and its end does not suspend")
  func foregroundDuringWork() {
    let (controller, recorder) = makeController()
    controller.didEnterBackground()
    controller.beginBackgroundWork()
    controller.willEnterForeground()
    controller.endBackgroundWork()
    #expect(recorder.calls == [.suspend, .resume, .requestTime, .releaseTime, .resume])
  }

  @Test("Leaving the app during work asks for time and keeps the writer open until the work ends")
  func backgroundDuringWork() {
    let (controller, recorder) = makeController()
    controller.beginBackgroundWork()
    controller.didEnterBackground()
    #expect(recorder.calls == [.requestTime])
    controller.endBackgroundWork()
    #expect(recorder.calls == [.requestTime, .suspend, .releaseTime])
  }

  @Test("When the time runs out, the writer is suspended even though work is still running")
  func expiryWithWorkRunning() {
    let (controller, recorder) = makeController()
    controller.beginBackgroundWork()
    controller.didEnterBackground()
    recorder.expire?()
    #expect(recorder.calls == [.requestTime, .suspend])
    // The overrunning work ending later suspends again (harmless) and has no
    // grant left to hand back.
    controller.endBackgroundWork()
    #expect(recorder.calls == [.requestTime, .suspend, .suspend])
  }

  @Test("New work after the time ran out opens the writer again with a new grant")
  func workAfterExpiry() {
    let (controller, recorder) = makeController()
    controller.didEnterBackground()
    controller.beginBackgroundWork()
    recorder.expire?()
    controller.beginBackgroundWork()
    #expect(
      recorder.calls == [.suspend, .resume, .requestTime, .suspend, .resume, .requestTime])
  }

  @Test("An expiry arriving after returning to the foreground leaves the writer open")
  func expiryInForeground() {
    let (controller, recorder) = makeController()
    controller.didEnterBackground()
    controller.beginBackgroundWork()
    let expire = recorder.expire
    controller.willEnterForeground()
    expire?()
    #expect(recorder.calls == [.suspend, .resume, .requestTime, .releaseTime, .resume])
  }

  @Test("In a background launch, work asks for time and suspends the writer when it ends")
  func backgroundLaunch() {
    let (controller, recorder) = makeController(isInBackground: true)
    controller.beginBackgroundWork()
    controller.endBackgroundWork()
    #expect(recorder.calls == [.resume, .requestTime, .suspend, .releaseTime])
  }

  @Test("Work that starts and ends in the foreground never touches the writer")
  func foregroundWork() async {
    let (controller, recorder) = makeController()
    let value = await controller.performBackgroundWork { 42 }
    #expect(value == 42)
    #expect(recorder.calls.isEmpty)
  }

  @Test("performBackgroundWork ends the work when the body throws")
  func performEndsOnThrow() async {
    struct Failure: Error {}
    let (controller, recorder) = makeController(isInBackground: true)
    await #expect(throws: Failure.self) {
      try await controller.performBackgroundWork { throw Failure() }
    }
    #expect(recorder.calls == [.resume, .requestTime, .suspend, .releaseTime])
  }

  @Test(
    "Before it is attached the controller only counts; attaching takes the launch state and time source"
  )
  func attachAtLaunch() {
    let recorder = Recorder()
    let controller = DatabaseSuspensionController(
      suspend: { recorder.calls.append(.suspend) },
      resume: { recorder.calls.append(.resume) })
    controller.beginBackgroundWork()
    controller.endBackgroundWork()
    #expect(recorder.calls.isEmpty)

    controller.attach(isInBackground: true) { onExpire in
      recorder.calls.append(.requestTime)
      recorder.expire = onExpire
      return { recorder.calls.append(.releaseTime) }
    }
    controller.beginBackgroundWork()
    controller.endBackgroundWork()
    #expect(recorder.calls == [.resume, .requestTime, .suspend, .releaseTime])
  }
}
