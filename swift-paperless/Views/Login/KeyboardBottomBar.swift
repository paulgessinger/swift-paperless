//
//  KeyboardBottomBar.swift
//  swift-paperless
//

import SwiftUI

/// Pins a bar to the bottom edge, above the keyboard while it is up.
///
/// Moving focus between a plain and a secure text field makes iOS drop the
/// AutoFill bar above the keyboard for a few frames, and the bar would dip and
/// pop back with it. A small drop in the keyboard's height is held off with
/// padding and only followed if it is still there a moment later.
private struct KeyboardBottomBar<Bar: View>: ViewModifier {
  @ViewBuilder var bar: () -> Bar

  /// The bottom inset as the system reports it, keyboard included.
  @State private var inset: CGFloat = 0
  /// The inset the bar is placed for; lags behind small drops.
  @State private var heldInset: CGFloat = 0
  @State private var pendingDrop: Task<Void, Never>?

  private static var dropDelay: Duration { .milliseconds(250) }
  /// Drops larger than this are the keyboard going away and are followed at once.
  private static var dismissThreshold: CGFloat { 100 }

  func body(content: Content) -> some View {
    content
      .safeAreaInset(edge: .bottom) {
        bar()
          .padding(.bottom, max(0, heldInset - inset))
      }
      .background {
        GeometryReader { proxy in
          Color.clear
            .onChange(of: proxy.safeAreaInsets.bottom, initial: true) { _, new in
              update(to: new)
            }
        }
      }
  }

  private func update(to new: CGFloat) {
    pendingDrop?.cancel()
    pendingDrop = nil
    inset = new

    guard new < heldInset, heldInset - new < Self.dismissThreshold else {
      heldInset = new
      return
    }

    pendingDrop = Task {
      try? await Task.sleep(for: Self.dropDelay)
      guard !Task.isCancelled else { return }
      withAnimation(.smooth(duration: 0.25)) { heldInset = new }
    }
  }
}

extension View {
  /// Pins `bar` to the bottom edge and keeps it above the keyboard without
  /// following the brief dips iOS makes when focus moves between text fields.
  func keyboardBottomBar(@ViewBuilder _ bar: @escaping () -> some View) -> some View {
    modifier(KeyboardBottomBar(bar: bar))
  }
}
