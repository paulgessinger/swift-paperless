//
//  ExtensionDatabaseLifecycle.swift
//  AppShared
//
//  The app extension's side of `DatabaseSuspensionController`.
//

import Foundation
import Persistence

/// Feeds a ``Persistence/DatabaseSuspensionController`` in an app extension,
/// which has no `UIApplication` lifecycle.
///
/// The extension counts as in the background while its UI is gone or its host
/// app is in the background. iOS can freeze the process in either case, and a
/// finished request posts no host notification.
@MainActor
public final class ExtensionDatabaseLifecycle {
  private let suspension: DatabaseSuspensionController

  private var isPresented = false
  private var isHostInBackground = false
  private var isInBackground = false

  init(suspension: DatabaseSuspensionController) {
    self.suspension = suspension
  }

  /// The extension's UI is about to show. A process can be reused for another
  /// request, with host notifications missed while it was frozen; a request
  /// only starts from a host in the foreground.
  public func willAppear() {
    isPresented = true
    isHostInBackground = false
    update()
  }

  /// The UI is gone. Call it before `completeRequest`, so the writer is
  /// suspended before iOS can freeze the process.
  public func didDisappear() {
    isPresented = false
    update()
  }

  func hostDidEnterBackground() {
    isHostInBackground = true
    update()
  }

  func hostWillEnterForeground() {
    isHostInBackground = false
    update()
  }

  private func update() {
    let inBackground = !isPresented || isHostInBackground
    guard inBackground != isInBackground else { return }
    isInBackground = inBackground
    if inBackground {
      suspension.didEnterBackground()
    } else {
      suspension.willEnterForeground()
    }
  }
}

/// The extensions' ``Persistence/DatabaseSuspensionController/RequestTime``:
/// time to keep running in the background, from
/// `ProcessInfo.performExpiringActivity`.
@MainActor
public enum ExpiringActivityTime {
  /// Runs `block` the way `performExpiringActivity` does: once on a concurrent
  /// queue, with `expired` true if there is no time. While it runs with
  /// `expired` false the process holds the time, and a second call with
  /// `expired` true says the time is up. Both calls have to return.
  typealias Activity = @Sendable (_ block: @escaping @Sendable (_ expired: Bool) -> Void) -> Void

  static func request(
    activity: Activity, onExpire: @escaping @MainActor @Sendable () -> Void
  ) -> @MainActor () -> Void {
    let grant = Grant(onExpire: onExpire)
    activity { expired in grant.run(expired: expired) }
    return { grant.release() }
  }

  /// One activity. `onExpire` fires at most once and never after `release()`,
  /// because a late expiry would otherwise be taken for the controller's next
  /// grant.
  @MainActor
  private final class Grant {
    private nonisolated let finished = DispatchSemaphore(value: 0)
    private var onExpire: (@MainActor @Sendable () -> Void)?

    init(onExpire: @escaping @MainActor @Sendable () -> Void) {
      self.onExpire = onExpire
    }

    nonisolated func run(expired: Bool) {
      if expired {
        // Synchronous: the time ends when this returns, and the writer has to
        // be suspended by then.
        DispatchQueue.main.sync { MainActor.assumeIsolated { expire() } }
      } else {
        finished.wait()
      }
    }

    func release() {
      onExpire = nil
      finished.signal()
    }

    private func expire() {
      let onExpire = onExpire
      self.onExpire = nil
      onExpire?()
      finished.signal()
    }
  }
}

#if os(iOS)
  extension ExpiringActivityTime {
    public static func request(
      onExpire: @escaping @MainActor @Sendable () -> Void
    ) -> @MainActor () -> Void {
      request(
        activity: { block in
          ProcessInfo.processInfo.performExpiringActivity(
            withReason: "Database writes", using: block)
        },
        onExpire: onExpire)
    }
  }

  extension ExtensionDatabaseLifecycle {
    /// The process's lifecycle, attached to ``AppStackHolder/suspension``.
    public static let shared: ExtensionDatabaseLifecycle = {
      let suspension = AppStackHolder.suspension
      suspension.attach(isInBackground: false, requestTime: ExpiringActivityTime.request)
      let lifecycle = ExtensionDatabaseLifecycle(suspension: suspension)

      // `queue: nil` to run synchronously where possible: a queued block could
      // land after the process was already frozen. The posting thread is not
      // documented, so this does not assume it is the main one.
      let center = NotificationCenter.default
      center.addObserver(
        forName: .NSExtensionHostDidEnterBackground, object: nil, queue: nil
      ) { _ in
        onMainActor { lifecycle.hostDidEnterBackground() }
      }
      center.addObserver(
        forName: .NSExtensionHostWillEnterForeground, object: nil, queue: nil
      ) { _ in
        onMainActor { lifecycle.hostWillEnterForeground() }
      }
      return lifecycle
    }()

    private nonisolated static func onMainActor(_ body: @escaping @MainActor @Sendable () -> Void) {
      if Thread.isMainThread {
        MainActor.assumeIsolated(body)
      } else {
        Task { @MainActor in body() }
      }
    }
  }
#endif
