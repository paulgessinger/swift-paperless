//
//  TextField+clearable.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.09.2024.
//
import SwiftUI

public struct ClearableModifier: ViewModifier {
  @Binding public var text: String
  @FocusState public var focused: Bool
  @Environment(\.isEnabled) private var isEnabled

  public func body(content: Content) -> some View {
    HStack {
      content
        .focused($focused)  // @TODO: This is probably not ideal if I want to manage focus externally.

      if isEnabled {
        Spacer()

        Label(String(localized: .localizable(.clearText)), systemImage: "xmark.circle.fill")
          .labelStyle(.iconOnly)
          .foregroundColor(.gray)
          .onTapGesture {
            text = ""
            focused = true
          }
          .opacity(text.isEmpty ? 0 : 1)
      }
    }
  }
}

extension TextField {
  @MainActor
  public func clearable(_ text: Binding<String>) -> some View {
    let m = ClearableModifier(text: text)
    return modifier(m)
  }
}
