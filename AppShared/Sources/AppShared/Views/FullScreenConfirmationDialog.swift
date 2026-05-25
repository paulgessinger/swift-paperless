//
//  FullScreenConfirmationDialog.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.12.24.
//

import SwiftUI

private struct FullScreenConfirmationDialog<M>: ViewModifier where M: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  @Binding public var isPresented: Bool

  public var title: String
  @ViewBuilder public var dialogContent: () -> M

  public func body(content: Content) -> some View {
    if horizontalSizeClass == .compact {
      content
        .confirmationDialog(
          String(localized: .localizable(.confirmationPromptTitle)), isPresented: $isPresented,
          titleVisibility: .visible
        ) {
          dialogContent()
        }
    } else {
      content
        .alert(title, isPresented: $isPresented) {
          dialogContent()
        }
    }
  }
}

extension View {
  @MainActor
  public func fullScreenConfirmationDialog(
    _ title: String, isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> some View
  ) -> some View {
    modifier(
      FullScreenConfirmationDialog(isPresented: isPresented, title: title, dialogContent: content))
  }
}
