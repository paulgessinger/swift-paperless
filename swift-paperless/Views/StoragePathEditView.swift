//
//  StoragePathEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import DataModel
import SwiftUI

struct StoragePathEditView<Element>: View where Element: StoragePathProtocol {
    @State private var storagePath: Element
    var onSave: (Element) throws -> Void

    private var saveLabel: String

    init(element storagePath: Element,
         onSave: @escaping (Element) throws -> Void)
    {
        _storagePath = State(initialValue: storagePath)
        self.onSave = onSave
        saveLabel = String(localized: .localizable(.save))
    }

    var isValid: Bool {
        !storagePath.name.isEmpty && !storagePath.path.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: .localizable(.title)), text: $storagePath.name)
                    .clearable($storagePath.name)

                TextField(String(localized: .localizable(.path)), text: $storagePath.path)
                    .clearable($storagePath.path)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)

            } header: {
                Text(.localizable(.properties))
            } footer: {
                Text(.localizable(.storagePathFormatExplanation))
            }

            MatchEditView(element: $storagePath)
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(saveLabel) {
                    do {
                        try onSave(storagePath)
                    } catch {
                        print("Save storage path error: \(error)")
                    }
                }
                .disabled(!isValid)
                .bold()
            }
        }

        .navigationTitle(Element.self is SavedView.Type ? String(localized: .localizable(.storagePathEditTitle)) : String(localized: .localizable(.storagePathCreateTitle)))

        .navigationBarTitleDisplayMode(.inline)
    }
}

extension StoragePathEditView where Element == ProtoStoragePath {
    init(onSave: @escaping (Element) throws -> Void = { _ in }) {
        self.init(element: ProtoStoragePath(), onSave: onSave)
        saveLabel = String(localized: .localizable(.add))
    }
}

struct EditStoragePath_Previews: PreviewProvider {
    struct Container: View {
        @State var path = ProtoStoragePath()
        var body: some View {
            StoragePathEditView(element: path, onSave: { _ in })
        }
    }

    static var previews: some View {
        Container()
    }
}
