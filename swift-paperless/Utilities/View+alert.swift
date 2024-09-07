//
//  View+alert.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 24.04.2024.
//

import SwiftUI

private struct AlertModifier<Item: Sendable, M: View, A: View>: ViewModifier {
    @Binding var item: Item?

    var title: (Binding<Item>) -> Text
    var actions: (Binding<Item>) -> M
    var message: ((Binding<Item>) -> A)?

    var titleText: Text {
        item == nil ? Text("nil") : title(Binding($item)!)
    }

    func body(content: Content) -> some View {
        content
            .alert(titleText, isPresented: .present($item),
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
    func alert<Item: Sendable>(
        unwrapping item: Binding<Item?>,
        title: @escaping (Binding<Item>) -> Text,
        @ViewBuilder actions: @escaping (Binding<Item>) -> some View,
        @ViewBuilder message: @escaping (Binding<Item>) -> some View
    ) -> some View {
        modifier(AlertModifier(item: item, title: title, actions: actions, message: message))
    }

    func alert<Item: Sendable>(
        unwrapping item: Binding<Item?>,
        title: @escaping (Binding<Item>) -> Text,
        @ViewBuilder actions: @escaping (Binding<Item>) -> some View
    ) -> some View {
        modifier(AlertModifier(item: item, title: title, actions: actions, message: { _ in EmptyView() }))
    }
}
