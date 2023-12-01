//
//  SavedViewEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.04.23.
//

import SwiftUI

struct SavedViewEditView<Element>: View where Element: SavedViewProtocol {
    @State private var savedView: Element
    var onSave: (Element) throws -> Void

    private var saveLabel: String

    init(element savedView: Element,
         onSave: @escaping (Element) throws -> Void)
    {
        _savedView = State(initialValue: savedView)
        self.onSave = onSave
        saveLabel = String(localized: "Save", comment: "Saved view edit")
    }

    var body: some View {
        Form {
            Section("Properties") {
                TextField("Title", text: $savedView.name)
                    .clearable($savedView.name)

                Toggle("Show on dashboard", isOn: $savedView.showOnDashboard)

                Toggle("Show in sidebar", isOn: $savedView.showInSidebar)
            }

            Section("Sorting") {
                Picker("Sort by", selection: $savedView.sortField) {
                    ForEach(SortField.allCases, id: \.self) { v in
                        Text(v.label).tag(v)
                    }
                }

                Picker("Sort order", selection: $savedView.sortOrder) {
                    Text("Ascending").tag(SortOrder.ascending)
                    Text("Descending").tag(SortOrder.descending)
                }
            }
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    do {
                        try onSave(savedView)
                    } catch {
                        print("Save saved view error: \(error)")
                    }
                }
                .disabled(savedView.name.isEmpty)
                .bold()
            }
        }

        .navigationTitle(Element.self is SavedView.Type ? "Edit saved view" : "Create saved view")

        .navigationBarTitleDisplayMode(.inline)
    }
}

extension SavedViewEditView where Element == ProtoSavedView {
    init(onSave: @escaping (Element) throws -> Void = { _ in }) {
        self.init(element: ProtoSavedView(), onSave: onSave)
        saveLabel = String(localized: "Add", comment: "Save saved view")
    }
}

struct EditSavedView_Previews: PreviewProvider {
    struct Container: View {
        @State var view = ProtoSavedView(name: "")
        var body: some View {
            SavedViewEditView(element: view, onSave: { _ in })
        }
    }

    static var previews: some View {
        Container()
    }
}
