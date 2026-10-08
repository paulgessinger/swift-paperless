import Foundation
import os

/// Decides when the database writer is suspended, so iOS never freezes the
/// process holding a lock on the shared database (`0xDEAD10CC`).
///
/// In the background the writer is open only while counted work runs and iOS
/// has granted time. It is suspended before the time is handed back, and as
/// soon as the time runs out, even with work still running.
@MainActor
public final class DatabaseSuspensionController {
  /// Asks iOS for time. Calls `onExpire` shortly before the time runs out, and
  /// returns a closure that hands it back early. The provider ends the grant
  /// itself after `onExpire`.
  public typealias RequestTime =
    @MainActor (_ onExpire: @escaping @MainActor @Sendable () -> Void) -> @MainActor () -> Void

  private let suspend: @MainActor () -> Void
  private let resume: @MainActor () -> Void
  private var requestTime: RequestTime

  private var isInBackground: Bool
  private var activeWork = 0
  /// Hands the held grant back; `nil` while none is held.
  private var releaseGrant: (@MainActor () -> Void)?

  /// - Parameter requestTime: The default grants none, so the controller only
  ///   counts until ``attach(isInBackground:requestTime:)``.
  public init(
    isInBackground: Bool = false,
    suspend: @escaping @MainActor () -> Void = { Database.suspend() },
    resume: @escaping @MainActor () -> Void = { Database.resume() },
    requestTime: @escaping RequestTime = { _ in {} }
  ) {
    self.isInBackground = isInBackground
    self.suspend = suspend
    self.resume = resume
    self.requestTime = requestTime
  }

  /// Connects the controller to the app's lifecycle at launch.
  ///
  /// - Parameter isInBackground: True for a launch straight into the
  ///   background, which never receives `didEnterBackground`.
  public func attach(isInBackground: Bool, requestTime: @escaping RequestTime) {
    self.isInBackground = isInBackground
    self.requestTime = requestTime
  }

  // MARK: - Lifecycle

  public func didEnterBackground() {
    isInBackground = true
    if activeWork == 0 {
      suspend()
    } else {
      Logger.persistence.notice(
        "Entered background with \(self.activeWork) background work item(s); requesting time")
      holdGrant()
    }
  }

  public func willEnterForeground() {
    isInBackground = false
    releaseHeldGrant()
    resume()
  }

  // MARK: - Work

  /// Counts one piece of work. In the background this opens the writer and
  /// asks for time, unless a grant is already held.
  public func beginBackgroundWork() {
    activeWork += 1
    if isInBackground, releaseGrant == nil {
      resume()
      holdGrant()
    }
  }

  public func endBackgroundWork() {
    guard activeWork > 0 else {
      assertionFailure("endBackgroundWork() without a matching beginBackgroundWork()")
      return
    }
    activeWork -= 1
    guard activeWork == 0 else { return }
    // Suspend first: iOS may freeze the process as soon as it has the time back.
    if isInBackground {
      suspend()
    }
    releaseHeldGrant()
  }

  /// Runs `body` as one piece of work.
  public func performBackgroundWork<T>(
    _ body: @MainActor () async throws -> T
  ) async rethrows -> T {
    beginBackgroundWork()
    defer { endBackgroundWork() }
    return try await body()
  }

  // MARK: - Time

  private func holdGrant() {
    guard releaseGrant == nil else { return }
    releaseGrant = requestTime { [weak self] in self?.grantExpired() }
  }

  private func releaseHeldGrant() {
    releaseGrant?()
    releaseGrant = nil
  }

  private func grantExpired() {
    releaseGrant = nil
    guard isInBackground else { return }
    Logger.persistence.notice(
      "Background time expired with \(self.activeWork) work item(s) running; suspending")
    suspend()
  }
}
