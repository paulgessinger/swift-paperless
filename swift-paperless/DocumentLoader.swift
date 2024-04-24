//
//  DocumentLoader.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.04.23.
//

import SwiftUI

struct BindingHelper<Element, Content: View>: View {
    @State var element: Element
    @ViewBuilder var content: (Binding<Element>) -> Content

    var body: some View {
        content($element)
    }
}
