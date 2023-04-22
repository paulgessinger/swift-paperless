//
//  EditSavedView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.04.23.
//

import SwiftUI

struct EditSavedView<S>: View where S: SavedViewProtocol {
    @Binding var outSavedView: S
    @State private var savedView: S
    var onSave: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    init(savedView: Binding<S>, onSave: @escaping () -> Void = {}) {
        self._outSavedView = savedView
        self._savedView = State(initialValue: savedView.wrappedValue)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Properties") {
                    TextField("Title", text: self.$savedView.name)
                        .clearable(self.$savedView.name)

                    Toggle("Show on dashboard", isOn: $savedView.showOnDashboard)

                    Toggle("Show in sidebar", isOn: $savedView.showInSidebar)
                }

                Section("Sorting") {
                    Picker("Sort by", selection: $savedView.sortField) {
                        ForEach(SortField.allCases, id: \.self) { v in
                            Text("\(v.label)").tag(v)
                        }
                    }

                    Picker("Sort order", selection: $savedView.sortOrder) {
                        Text("Ascending").tag(SortOrder.ascending)
                        Text("Descending").tag(SortOrder.descending)
                    }

//                    let b = Binding<Bool>(
//                        get: { savedView.sortOrder.reverse },
//                        set: { savedView.sortOrder = .init($0) }
//                    )
//                    Toggle(isOn: b) {
//                        let l: String = {
//                            switch savedView.sortOrder {
//                            case .ascending: return "Ascending"
//                            case .descending: return "Descending"
//                            }
//                        }()
//                        Text(l)
//                    }
                }
            }

            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        self.dismiss()
                    }
                    .foregroundColor(.accentColor) // why is this needed? It's not elsewhere
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        outSavedView = savedView
                        onSave()
                        self.dismiss()
                    }
                    .disabled(savedView.name.isEmpty)
                    .bold()
                    .foregroundColor(.accentColor) // why is this needed? It's not elsewhere
                }
            }

            .navigationTitle("Saved view")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
    }
}

struct EditSavedView_Previews: PreviewProvider {
    struct Container: View {
        @State var view = ProtoSavedView(name: "")
        var body: some View {
            EditSavedView(savedView: $view)
        }
    }

    static var previews: some View {
        Container()
    }
}
