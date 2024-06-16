//
//  ExtraHeadersView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 07.05.23.
//

import os
import SwiftUI

struct ExtraHeadersView: View {
    @Binding var headers: [ConnectionManager.HeaderValue]

    private struct SingleView: View {
        @Binding var header: ConnectionManager.HeaderValue

//        var headerKey: Binding<String> {
//            return Binding<String>(get: {header.key}, set: {
//                print("Sanitizing: '\($0)'")
//                header.key = $0.replacingOccurrences(of: " ", with: "")
//                print("now: '\(header.key)'")
//            })
//        }

        var body: some View {
            Form {
                Section(String(localized: .login(.extraHeadersKey))) {
                    TextField(String(localized: .login(.extraHeadersKey)), text: $header.key)
                        .clearable($header.key)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .onChange(of: header.key) { _, value in
                            header.key = value.replacingOccurrences(of: " ", with: "")
                        }
                }
                Section(String(localized: .login(.extraHeadersValue))) {
                    TextField(String(localized: .login(.extraHeadersValue)), text: $header.value)
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
                ForEach($headers, id: \.id) { $header in
                    NavigationLink {
                        SingleView(header: $header)
                    } label: {
                        LabeledContent(header.key, value: header.value)
                    }
                }
                .onDelete { ids in
                    withAnimation {
                        headers.remove(atOffsets: ids)
                    }
                }
            } footer: {
                Text(.login(.extraHeadersDescription))
            }
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button {
                        withAnimation {
                            headers.append(.init(key: "Header", value: "Value"))
                        }
                    } label: {
                        Label(String(localized: .localizable(.add)), systemImage: "plus")
                    }
                    EditButton()
                }
            }
        }

        .navigationTitle(Text(.login(.extraHeaders)))
    }
}
