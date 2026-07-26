import Persistence
import SwiftUI

extension View {
  /// Listen to a ``Broadcaster`` for the lifetime of this view's `@State`
  /// storage. Shape matches `.onReceive(publisher:perform:)` but is backed by
  /// an `AsyncStream` subscription whose `Task` outlives view
  /// disappear/reappear cycles (NavigationStack push/pop) — `.task` and
  /// `for await` would cancel on disappear and drop events.
  public func onEvent<Element>(
    from broadcaster: Broadcaster<Element>,
    perform action: @escaping @MainActor (Element) -> Void
  ) -> some View {
    modifier(BroadcasterEventModifier(broadcaster: broadcaster, action: action))
  }
}

/// Indirection so the long-lived subscription always invokes the handler from
/// the *current* view value.
///
/// The subscription is created once and deliberately outlives disappear /
/// reappear, so it cannot capture the handler directly: a closure captured at
/// first appear would read stale `let`/`var` view properties forever.
/// `.onReceive` gets this for free — its `SubscriptionView` swaps in the
/// latest closure on every update — so matching that shape means refreshing
/// the handler by hand on each `body` evaluation.
///
/// `@unchecked Sendable`: `action` is written in `body` and read in the sink
/// handler, both of which are main-actor isolated.
private final class EventActionBox<Element>: @unchecked Sendable {
  var action: (@MainActor (Element) -> Void)?
}

private struct BroadcasterEventModifier<Element: Sendable>: ViewModifier {
  let broadcaster: Broadcaster<Element>
  let action: @MainActor (Element) -> Void

  @State private var box = EventActionBox<Element>()
  @State private var subscription: Subscription?

  func body(content: Content) -> some View {
    box.action = action

    return
      content
      .onAppear {
        if subscription == nil {
          subscription = makeSubscription()
        }
      }
      // A broadcaster swapped underneath a live view would otherwise keep
      // delivering from the old one.
      .onChange(of: ObjectIdentifier(broadcaster)) { _, _ in
        subscription?.cancel()
        subscription = makeSubscription()
      }
  }

  private func makeSubscription() -> Subscription {
    let box = box
    return broadcaster.sink { element in
      box.action?(element)
    }
  }
}
