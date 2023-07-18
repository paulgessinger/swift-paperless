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
        VStack {
            if document != nil {
                content(Binding(unwrapping: self.$document)!)
            }
            else {
                ProgressView()
            }
        }
        .task {
            document = await store.repository.documents(filter: .init()).fetch(limit: 999).first!
        }
    }
}
