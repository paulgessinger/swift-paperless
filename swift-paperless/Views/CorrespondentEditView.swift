//
//  CorrespondentEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.04.23.
//

import SwiftUI

struct CorrespondentEditView<Element>: View where Element: CorrespondentProtocol {
    @State private var element: Element
    var onSave: (Element) throws -> Void

    private var saveLabel: String

    init(element: Element, onSave: @escaping (Element) throws -> Void = { _ in }) {
        _element = State(initialValue: element)
        self.onSave = onSave
        saveLabel = String(localized: .localizable(.save))
    }

    private func valid() -> Bool {
        !element.name.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: .localizable(.name)), text: $element.name)
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
                        print("Save correspondent error: \(error)")
                    }
                }
                .disabled(!valid())
            }
        }
        .navigationTitle(Element.self is Correspondent.Type ? String(localized: .localizable(.correspondentEditTitle)) : String(localized: .localizable(.correspondentCreateTitle)))
    }
}

extension CorrespondentEditView where Element == ProtoCorrespondent {
    init(onSave: @escaping (Element) throws -> Void = { _ in }) {
        self.init(element: ProtoCorrespondent(), onSave: onSave)
        saveLabel = String(localized: .localizable(.add))
    }
}

struct CorrespondentEditView_Previews: PreviewProvider {
    struct Container: View {
        var body: some View {
            NavigationStack {
                CorrespondentEditView<ProtoCorrespondent>()
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle(Text(.localizable(.correspondentCreateTitle)))
            }
        }
    }

    static var previews: some View {
        Container()
    }
}
