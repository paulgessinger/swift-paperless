//
//  KeyboardDismisser.swift
//  swift-paperless
//

import SwiftUI
import UIKit

/// Forces the keyboard to resign, regardless of which responder currently
/// owns it. Needed because a `@FocusState` binding can only resign a
/// responder it owns; after popping back from a pushed view (e.g. a picker
/// with its own search field), the keyboard can be left attached to a
/// responder that already went away, which a local FocusState reset can't
/// reach.
private struct KeyboardDismisser: UIViewRepresentable {
  @Binding var trigger: Bool

  func makeUIView(context: Context) -> UIView {
    UIView(frame: .zero)
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    guard trigger else { return }
    DispatchQueue.main.async {
      uiView.window?.endEditing(true)
      trigger = false
    }
  }
}

extension View {
  public func dismissKeyboard(trigger: Binding<Bool>) -> some View {
    background(KeyboardDismisser(trigger: trigger))
  }
}
