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
                Section(String(localized: .login.extraHeadersKey)) {
                    TextField(String(localized: .login.extraHeadersKey), text: $header.key)
                        .clearable($header.key)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
                Section(String(localized: .login.extraHeadersValue)) {
                    TextField(String(localized: .login.extraHeadersValue), text: $header.value)
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
                    } label: { Text(String("\(tup.key): \(tup.value)")) }
                }
                .onDelete { ids in
                    withAnimation {
                        headers.remove(atOffsets: ids)
                    }
                }
            } footer: {
                Text(.login.extraHeadersDescription)
            }
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation {
                        headers.append(.init(key: "Header", value: "Value"))
                    }
                } label: {
                    Label(String(localized: .localizable.add), systemImage: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .navigationTitle(Text(.login.extraHeaders))
    }
}
