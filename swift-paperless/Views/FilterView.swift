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

    init() {}

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $filterState.correspondent,
                           content: {
                               Text("None").tag(nil as UInt?)
                               ForEach(store.correspondents.sorted { $0.value.name < $1.value.name }, id: \.value.id) { _, c in
                                   Text("\(c.name)").tag(c.id as UInt?)
                               }
                           },
                           label: {
                               Text("Correspondent")
                           })

                    Picker("Document type", selection: $filterState.documentType) {
                        Text("None").tag(nil as UInt?)
                        ForEach(store.documentTypes.sorted { $0.value.name < $1.value.name }, id: \.value.id) { _, c in
                            Text("\(c.name)").tag(c.id as UInt?)
                        }
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        print("Store")
                        store.setFilterState(to: filterState)
                        dismiss()
                    }.bold()
                }
            }
        }.onAppear {
            self.filterState = store.filterState
        }
    }
}
