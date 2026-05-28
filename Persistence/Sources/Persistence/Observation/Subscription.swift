import Foundation

/// A handle to a long-lived task that will be cancelled when the handle
/// deallocates, matching the lifecycle shape of Combine's `AnyCancellable`.
///
/// Designed to be stored in SwiftUI `@State`-owned containers (typically
/// `Set<Subscription>`) so the underlying `Task` survives view appearance
/// cycles — particularly NavigationStack push/pop where the parent view
/// transiently "disappears" — and is torn down only when the view's state
/// storage is freed.
public final class Subscription: @unchecked Sendable, Hashable {
  private let task: Task<Void, Never>

  init(_ task: Task<Void, Never>) {
    self.task = task
  }

  /// Cancel the underlying task immediately. The Subscription itself stays
  /// allocated until its container releases it.
  public func cancel() {
    task.cancel()
  }

  deinit {
    task.cancel()
  }

  public static func == (lhs: Subscription, rhs: Subscription) -> Bool {
    lhs === rhs
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

extension Subscription {
  /// Store the subscription in a `Set`, matching Combine's
  /// `AnyCancellable.store(in:)` shape.
  public func store(in set: inout Set<Subscription>) {
    set.insert(self)
  }

  /// Store the subscription in any range-replaceable collection
  /// (e.g. `[Subscription]`).
  public func store<C: RangeReplaceableCollection>(in collection: inout C)
  where C.Element == Subscription {
    collection.append(self)
  }
}

extension Broadcaster {
  /// Subscribe with a handler closure and return a ``Subscription`` whose
  /// lifetime owns the underlying receive task. Cancel by calling
  /// ``Subscription/cancel()`` or by releasing the handle (typically via
  /// the `Set<Subscription>` it was stored in).
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

#if canImport(SwiftUI)
  import SwiftUI

  extension View {
    /// Listen to a ``Broadcaster`` for the lifetime of this view's `@State`
    /// storage. Shape matches `.onReceive(publisher:perform:)` but is
    /// backed by an `AsyncStream` subscription whose `Task` outlives view
    /// disappear/reappear cycles (NavigationStack push/pop) — `.task` and
    /// `for await` would cancel on disappear and drop events.
    public func onEvent<Element>(
      from broadcaster: Broadcaster<Element>,
      perform action: @escaping @MainActor (Element) -> Void
    ) -> some View {
      modifier(BroadcasterEventModifier(broadcaster: broadcaster, action: action))
    }
  }

  private struct BroadcasterEventModifier<Element: Sendable>: ViewModifier {
    let broadcaster: Broadcaster<Element>
    let action: @MainActor (Element) -> Void

    @State private var subscription: Subscription?

    func body(content: Content) -> some View {
      content.onAppear {
        if subscription == nil {
          subscription = broadcaster.sink(action)
        }
      }
    }
  }
#endif
