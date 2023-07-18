//
//  StoragePathEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

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
        saveLabel = "Save"
    }

    var isValid: Bool {
        !storagePath.name.isEmpty && !storagePath.path.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: self.$storagePath.name)
                    .clearable(self.$storagePath.name)

                TextField("Path", text: self.$storagePath.path)
                    .clearable(self.$storagePath.path)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)

            } header: {
                Text("Properties")
            } footer: {
                Text("storage_path_format_explanation")
            }

            MatchEditView(element: $storagePath)
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    do {
                        try onSave(storagePath)
                    }
                    catch {
                        print("Save storage path error: \(error)")
                    }
                }
                .disabled(!isValid)
                .bold()
            }
        }

        .navigationTitle(Element.self is SavedView.Type ? "Edit saved view" : "Create saved view")

        .navigationBarTitleDisplayMode(.inline)
    }
}

extension StoragePathEditView where Element == ProtoStoragePath {
    init(onSave: @escaping (Element) throws -> Void = { _ in }) {
        self.init(element: ProtoStoragePath(), onSave: onSave)
        saveLabel = "Add"
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
