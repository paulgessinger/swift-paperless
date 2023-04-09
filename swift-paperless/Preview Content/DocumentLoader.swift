//
//  DocumentLoader.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.04.23.
//

import SwiftUI

private struct BindingHelper<Content: View>: View {
    @State var document: Document
    @ViewBuilder var content: (Binding<Document>) -> Content

    var body: some View {
        content($document)
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
                BindingHelper(document: document, content: content)
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
