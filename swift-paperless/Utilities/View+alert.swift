//
//  View+alert.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 24.04.2024.
//

import SwiftUI

private struct AlertModifier<Item: Sendable, M: View, A: View>: ViewModifier {
  @Binding var item: Item?

  var title: (Item) -> Text
  var actions: (Item) -> M
  var message: ((Item) -> A)?

  var titleText: Text {
    if let item = Binding($item) {
      title(item.wrappedValue)
    } else {
      Text("nil")
    }
  }

  func body(content: Content) -> some View {
    content
      .alert(
        titleText, isPresented: .present($item),
        actions: {
          if let item = Binding($item) {
            actions(item.wrappedValue)
          } else {
            EmptyView()
          }
        },
        message: {
          if let item = Binding($item) {
            message?(item.wrappedValue)
          } else {
            EmptyView()
          }

        })
  }
}

extension View {
  func alert<Item: Sendable>(
    unwrapping item: Binding<Item?>,
    title: @escaping (Item) -> Text,
    @ViewBuilder actions: @escaping (Item) -> some View,
    @ViewBuilder message: @escaping (Item) -> some View
  ) -> some View {
    modifier(AlertModifier(item: item, title: title, actions: actions, message: message))
  }

  func alert<Item: Sendable>(
    unwrapping item: Binding<Item?>,
    title: @escaping (Item) -> Text,
    @ViewBuilder actions: @escaping (Item) -> some View
  ) -> some View {
    modifier(
      AlertModifier(item: item, title: title, actions: actions, message: { _ in EmptyView() }))
  }
}
