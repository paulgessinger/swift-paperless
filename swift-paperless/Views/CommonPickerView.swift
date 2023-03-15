//
//  CommonPickerView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI

struct CommonPicker: View {
    @Binding var selection: FilterState.Filter
    var elements: [(UInt, String)]

    var filterMode = true

    @StateObject private var searchDebounce = DebounceObject(delay: 0.1)

    func row(_ label: String, value: FilterState.Filter) -> some View {
        return HStack {
            Button(action: { selection = value }) {
                Text(label)
            }
            .foregroundColor(.primary)
            Spacer()
            if selection == value {
                Label("Active", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
            }
        }
    }

    private func filter(name: String) -> Bool {
        if searchDebounce.debouncedText.isEmpty { return true }
        if let _ = name.range(of: searchDebounce.debouncedText, options: .caseInsensitive) {
            return true
        }
        else {
            return false
        }
    }

    var body: some View {
        VStack {
            SearchBarView(text: $searchDebounce.debouncedText)
                .transition(.opacity)
                .padding(.horizontal)
                .padding(.vertical, 2)
            Form {
                Section {
                    if filterMode {
                        row("Any", value: FilterState.Filter.any)
                    }
                    row(filterMode ? "Not assigned" : "None", value: FilterState.Filter.notAssigned)
                }
                Section {
                    ForEach(elements.filter { filter(name: $0.1) },
                            id: \.0) { id, name in
                        row(name, value: FilterState.Filter.only(id: id))
                    }
                }
            }
            .overlay(
                Rectangle()
                    .fill(.gray)
                    .frame(maxWidth: .infinity, maxHeight: 1),
                alignment: .top
            )
        }
    }
}
