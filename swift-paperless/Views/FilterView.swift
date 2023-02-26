//
//  FilterView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI

struct FilterView: View {
    @Environment(\.dismiss) var dismiss

    @EnvironmentObject var store: DocumentStore

    @State var filterState: FilterState = .init()
    @State var modified: Bool = false

//    @Binding var filterState: FilterState

    init(filterState: FilterState) {
        self._filterState = State(initialValue: filterState)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $filterState.correspondent,
                           content: {
                               Text("Any").tag(FilterState.Filter.any)
                               Text("Not Assigned").tag(FilterState.Filter.notAssigned)
                               ForEach(store.correspondents.sorted { $0.value.name < $1.value.name }, id: \.value.id) { _, c in
                                   Text("\(c.name)").tag(FilterState.Filter.only(id: c.id))
                               }
                           },
                           label: {
                               Text("Correspondent")
                           })

                    Picker("Document type", selection: $filterState.documentType) {
                        Text("Any").tag(FilterState.Filter.any)
                        Text("Not Assigned").tag(FilterState.Filter.notAssigned)
                        ForEach(store.documentTypes.sorted { $0.value.name < $1.value.name }, id: \.value.id) { _, c in
                            Text("\(c.name)").tag(FilterState.Filter.only(id: c.id))
                        }
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear", role: .cancel) {
                        store.filterState = FilterState()
                        dismiss()
                    }
                }

                if modified {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Discard") {
                            filterState = store.filterState
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        print("Store")
//                        store.setFilterState(to: filterState)
//                        outputFilterState = filterState
                        store.filterState = filterState
                        dismiss()
                    }.bold()
                }
            }
            .onChange(of: filterState) { _ in
                modified = filterState != store.filterState
            }
            .interactiveDismissDisabled(modified)
        }
    }
}
