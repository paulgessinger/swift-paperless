//
//  KeyboardStateModifier.swift
//  swift-paperless
//

import SwiftUI
import UIKit

@MainActor
struct KeyboardStateModifier: ViewModifier {
  @Binding var isSoftwareKeyboardVisible: Bool
  @Binding var keyboardHeight: CGFloat

  func body(content: Content) -> some View {
    content.task {
      await withTaskGroup(of: Void.self) { group in
        group.addTask {
          for await notification in NotificationCenter.default.notifications(
            named: UIResponder.keyboardWillShowNotification
          ) {
            guard
              let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else {
              continue
            }
            await MainActor.run {
              keyboardHeight = frame.height
              isSoftwareKeyboardVisible = frame.height > 100
            }
          }
        }
        group.addTask {
          for await _ in NotificationCenter.default.notifications(
            named: UIResponder.keyboardWillHideNotification
          ) {
            await MainActor.run {
              keyboardHeight = 0
              isSoftwareKeyboardVisible = false
            }
          }
        }
      }
    }
  }
}

extension View {
  func trackKeyboardState(
    isVisible: Binding<Bool>,
    height: Binding<CGFloat> = .constant(0)
  ) -> some View {
    modifier(
      KeyboardStateModifier(
        isSoftwareKeyboardVisible: isVisible,
        keyboardHeight: height
      )
    )
  }
}
