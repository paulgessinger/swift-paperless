//
//  ExtraHeadersView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 07.05.23.
//

import SwiftUI

struct ExtraHeadersView: View {
    @Binding var headers: [ConnectionManager.HeaderValue]

    private struct SingleView: View {
        @Binding var header: ConnectionManager.HeaderValue
        var body: some View {
            Form {
                Section("Key") {
                    TextField("Key", text: $header.key)
                        .clearable($header.key)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
                Section("Value") {
                    TextField("Value", text: $header.value)
                        .clearable($header.value)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
            }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(0 ..< headers.count, id: \.self) { idx in
                    let tup = headers[idx]
                    NavigationLink {
                        SingleView(header: $headers[idx])
                    } label: { Text("\(tup.key): \(tup.value)") }
                }
                .onDelete { ids in
                    withAnimation {
                        headers.remove(atOffsets: ids)
                    }
                }
            } footer: {
                Text("Extra headers to include in all API requests that the app makes to your installation.")
            }
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation {
                        headers.append(.init(key: "Header", value: "Value"))
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .navigationTitle("Extra headers")
    }
}
