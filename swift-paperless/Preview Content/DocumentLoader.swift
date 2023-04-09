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

struct DocumentLoader<Content: View>: View {
    var id: UInt
    @ViewBuilder var content: (Binding<Document>) -> Content

    @State private var document: Document?
    @EnvironmentObject private var store: DocumentStore

    var body: some View {
        Group {
            if let document = document {
                BindingHelper(element: document, content: content)
            }
            else {
                ProgressView()
            }
        }
        .task {
            document = await store.document(id: id)!
        }
    }
}
