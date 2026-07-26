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

/// A mutable, `@State`-owned slot holding the *latest* handler closure, so the
/// long-lived subscription can call forward into the current view value instead
/// of the one that existed when it was created.
///
/// Why the indirection is needed: SwiftUI recreates the `ViewModifier` **struct**
/// on every update, and each new struct carries a fresh `action` closure that has
/// captured the current view's properties. The subscription, though, is created
/// once in `onAppear` and deliberately outlives disappear/reappear (that is the
/// whole point — see ``SwiftUICore/View/onEvent(from:perform:)``). If it captured
/// `action` directly, it would pin the *first* closure forever, and any plain
/// `let`/`var` view property that closure reads would be permanently stale.
///
/// `.onReceive` avoids this for free: its internal `SubscriptionView` is handed
/// the newest closure on every update. Matching that shape by hand means storing
/// the closure somewhere with view-lifetime identity (`@State`) and overwriting
/// it on each `body` evaluation — which is what this class is.
///
/// Only the *closure* is refreshed; the subscription and its `Task` are untouched,
/// so no events are dropped in the process.
///
/// `@unchecked Sendable`: `action` is written in `body` and read in the sink
/// handler, both of which are main-actor isolated.
private final class EventActionBox<Element>: @unchecked Sendable {
  var action: (@MainActor (Element) -> Void)?
}

private struct BroadcasterEventModifier<Element: Sendable>: ViewModifier {
  let broadcaster: Broadcaster<Element>
  let action: @MainActor (Element) -> Void

  // Both need view-lifetime identity, not struct-lifetime: `@State` survives the
  // struct being recreated on every update.
  @State private var box = EventActionBox<Element>()
  @State private var subscription: Subscription?

  func body(content: Content) -> some View {
    // Hand the current closure to the box on every update — see ``EventActionBox``.
    // Safe to do during `body`: the box is a plain class, so writing to it
    // invalidates nothing and cannot loop.
    box.action = action

    return
      content
      .onAppear {
        if subscription == nil {
          subscription = makeSubscription()
        }
      }
      // Resubscribe if a *different* broadcaster is passed in; otherwise events
      // would keep arriving from the old one. `Broadcaster` is a non-Equatable
      // reference type, so it can't be the `onChange` value directly —
      // `ObjectIdentifier` is the cheap Equatable stand-in for "same instance",
      // making this fire on identity change and never on content change.
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
