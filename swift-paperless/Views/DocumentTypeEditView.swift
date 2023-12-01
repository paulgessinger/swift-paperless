//
//  DocumentTypeEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.04.23.
//

import SwiftUI

struct DocumentTypeEditView<Element>: View where Element: DocumentTypeProtocol {
    @State private var element: Element
    var onSave: (Element) throws -> Void

    private var saveLabel: String

    init(element: Element, onSave: @escaping (Element) throws -> Void = { _ in }) {
        _element = State(initialValue: element)
        self.onSave = onSave
        saveLabel = String(localized: "Save", comment: "Document type edit")
    }

    private func valid() -> Bool {
        !element.name.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $element.name)
                    .clearable($element.name)
            }

            MatchEditView(element: $element)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(saveLabel) {
                    do {
                        try onSave(element)
                    } catch {
                        print("Save document type error: \(error)")
                    }
                }
                .disabled(!valid())
            }
        }

        .navigationTitle(Element.self is DocumentType.Type ? "Edit document type" : "Create document type")
    }
}

extension DocumentTypeEditView where Element == ProtoDocumentType {
    init(onSave: @escaping (Element) throws -> Void = { _ in }) {
        self.init(element: ProtoDocumentType(), onSave: onSave)
        saveLabel = String(localized: "Add", comment: "Save document type")
    }
}

struct DocumentTypeEditView_Previews: PreviewProvider {
    struct Container: View {
        var body: some View {
            NavigationStack {
                DocumentTypeEditView<ProtoDocumentType>()
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle("Create document type")
            }
        }
    }

    static var previews: some View {
        Container()
    }
}
