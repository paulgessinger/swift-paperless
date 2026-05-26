//
//  View+confirmationDialog.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 24.04.2024.
//

import SwiftUI

private struct ConfirmationDialogModifier<Item: Sendable, M: View, A: View>: ViewModifier {
  @Binding public var item: Item?

  public var title: (Binding<Item>) -> String
  public var actions: (Binding<Item>) -> M
  public var message: ((Binding<Item>) -> A)?

  public var titleString: String {
    item == nil ? "nil" : title(Binding($item)!)
  }

  public func body(content: Content) -> some View {
    content
      .confirmationDialog(
        titleString, isPresented: .present($item),
        actions: {
          if let item = Binding($item) {
            actions(item)
          } else {
            EmptyView()
          }
        },
        message: {
          if let item = Binding($item) {
            message?(item)
          } else {
            EmptyView()
          }

        })
  }
}

extension View {
  public func confirmationDialog<Item: Sendable>(
    unwrapping item: Binding<Item?>,
    title: @escaping (Binding<Item>) -> String,
    @ViewBuilder actions: @escaping (Binding<Item>) -> some View,
    @ViewBuilder message: @escaping (Binding<Item>) -> some View
  ) -> some View {
    modifier(
      ConfirmationDialogModifier(item: item, title: title, actions: actions, message: message))
  }

  public func confirmationDialog<Item: Sendable>(
    unwrapping item: Binding<Item?>,
    title: @escaping (Binding<Item>) -> String,
    @ViewBuilder actions: @escaping (Binding<Item>) -> some View
  ) -> some View {
    modifier(
      ConfirmationDialogModifier(
        item: item, title: title, actions: actions, message: { _ in EmptyView() }))
  }
}
