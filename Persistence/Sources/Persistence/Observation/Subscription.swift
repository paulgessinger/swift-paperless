import Foundation

/// A handle to a long-lived task that will be cancelled when the handle
/// deallocates, matching the lifecycle shape of Combine's `AnyCancellable`.
///
/// Designed to be held by SwiftUI `@State` storage so the underlying `Task`
/// survives view appearance cycles — particularly NavigationStack push/pop
/// where the parent view transiently "disappears" — and is torn down only
/// when the view's state storage is freed.
public final class Subscription: Sendable {
  private let task: Task<Void, Never>

  public init(_ task: Task<Void, Never>) {
    self.task = task
  }

  /// Cancel the underlying task immediately. The Subscription itself stays
  /// allocated until its owner releases it.
  public func cancel() {
    task.cancel()
  }

  deinit {
    task.cancel()
  }
}

extension Broadcaster {
  /// Subscribe with a handler closure and return a ``Subscription`` whose
  /// lifetime owns the underlying receive task. Cancel by calling
  /// ``Subscription/cancel()`` or by releasing the handle.
  ///
  /// Mirrors Combine's `Publisher.sink(receiveValue:)`. The handler runs on
  /// the main actor, matching `.onReceive`'s default delivery context for
  /// SwiftUI consumers.
  public func sink(
    _ handler: @escaping @MainActor (Element) -> Void
  ) -> Subscription {
    let stream = subscribe()
    let task = Task { @MainActor in
      for await element in stream {
        handler(element)
      }
    }
    return Subscription(task)
  }
}
