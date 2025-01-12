//
//  SavedViewEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.04.23.
//

import DataModel
import os
import SwiftUI

struct SavedViewEditView<Element>: View where Element: SavedViewProtocol {
    @State private var savedView: Element
    var onSave: ((Element) throws -> Void)?

    private var saveLabel: String

    init(element savedView: Element,
         onSave: ((Element) throws -> Void)?)
    {
        _savedView = State(initialValue: savedView)
        self.onSave = onSave
        saveLabel = String(localized: .localizable(.save))
    }

    var body: some View {
        Form {
            Section(String(localized: .localizable(.properties))) {
                TextField(String(localized: .localizable(.title)), text: $savedView.name)
                    .clearable($savedView.name)

                Toggle(String(localized: .localizable(.savedViewShowOnDashboard)), isOn: $savedView.showOnDashboard)

                Toggle(String(localized: .localizable(.savedViewShowInSidebar)), isOn: $savedView.showInSidebar)
            }

            Section(String(localized: .localizable(.sorting))) {
                Picker(String(localized: .localizable(.sortBy)), selection: $savedView.sortField) {
                    ForEach(SortField.allCases, id: \.rawValue) { v in
                        Text(v.localizedName).tag(v)
                    }
                }

                Picker(String(localized: .localizable(.sortOrder)), selection: $savedView.sortOrder) {
                    Text(DataModel.SortOrder.ascending.localizedName)
                        .tag(DataModel.SortOrder.ascending)
                    Text(DataModel.SortOrder.descending.localizedName)
                        .tag(DataModel.SortOrder.descending)
                }
            }
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(String(localized: .localizable(.save))) {
                    do {
                        try onSave?(savedView)
                    } catch {
                        Logger.shared.error("Save saved view error: \(error)")
                    }
                }
                .disabled(savedView.name.isEmpty)
                .bold()
            }
        }

        .navigationTitle(Element.self is SavedView.Type ? Text(.localizable(.savedViewEditTitle)) : Text(.localizable(.savedViewCreateTitle)))

        .navigationBarTitleDisplayMode(.inline)
    }
}

extension SavedViewEditView where Element == ProtoSavedView {
    init(onSave: @escaping (Element) throws -> Void) {
        self.init(element: ProtoSavedView(), onSave: onSave)
        saveLabel = String(localized: .localizable(.add))
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
