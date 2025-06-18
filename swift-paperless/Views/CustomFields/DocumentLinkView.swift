//
//  DocumentLinkView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 15.06.25.
//

import DataModel
import Flow
import Networking
import os
import SwiftUI

private struct SearchView: View {
    @Binding var instance: CustomFieldInstance
    @Binding var selected: [Document]

    @EnvironmentObject private var store: DocumentStore
    @State private var searchText = ""
    @State private var matchingDocuments: [Document] = []

    @State private var searchTask: Task<Void, Never>?
    @Namespace private var namespace

    var body: some View {
        List {
            Section(.customFields(.documentLinkSelectedLabel)) {
                ForEach(selected) { document in
                    Button {
                        selected = selected.filter { $0.id != document.id }
                    } label: {
                        HStack {
                            Text(document.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "checkmark.circle.fill")
                                .contentTransition(.symbolEffect)
                        }
                    }
                }
            }

            Section {
                let show = matchingDocuments.filter {
                    !selected.contains($0)
                }
                ForEach(show) { document in
                    Button {
                        selected.append(document)
                    } label: {
                        HStack {
                            Text(document.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "plus.circle")
                                .contentTransition(.symbolEffect)
                        }
                    }
                }
            }
        }
        .animation(.spring, value: matchingDocuments)
        .animation(.spring, value: selected)
        .navigationTitle(instance.field.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: .customFields(.documentLinkSearchPlaceholder))

        .onChange(of: searchText) {
            guard searchText.count >= 3 else {
                matchingDocuments = []
                return
            }

            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .seconds(0.3))

                do {
                    matchingDocuments = try await store.repository.documents(containsTitle: searchText)
                } catch {
                    Logger.shared.error("Error searching documents: \(error, privacy: .public)")
                }
            }
        }
    }
}

struct DocumentLinkView: View {
    @Binding var instance: CustomFieldInstance

    @EnvironmentObject private var store: DocumentStore

    @State private var selected: [Document] = []

    @State private var initial = true

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
    }

    private var backgroundColor: Color {
        if #available(iOS 18.0, *) {
            Color.accentColor.mix(with: .white, by: 0.9)
        } else {
            Color.accentColor.opacity(0.1)
        }
    }

    private func loadSelected() async {
        guard initial else { return }
        initial = false

        if case let .documentLink(ids) = instance.value {
            Logger.shared.trace("Loading documents for \(ids.count) document links")
            selected = await withTaskGroup(of: Document?.self, returning: [Document].self) { group in
                for id in ids {
                    group.addTask {
                        do {
                            return try await store.repository.document(id: id)
                        } catch {
                            Logger.shared.error("Error loading document with ID \(id): \(error, privacy: .public)")
                            return nil
                        }
                    }
                }

                var documents = [Document]()

                await group.waitForAll()

                for await document in group {
                    if let document {
                        Logger.shared.trace("Loaded document: \(document.title, privacy: .public)")
                        documents.append(document)
                    }
                }
                return documents
            }
        }
    }

    var body: some View {
        Section(instance.field.name) {
            NavigationLink {
                SearchView(instance: $instance, selected: $selected)
            } label: {
                HStack {
                    HFlow {
                        ForEach(selected) { document in
                            HStack {
                                Image(systemName: "doc.text")

                                Text(document.title)
                            }
                            .lineLimit(1)
                            .padding(5)
                            .padding(.horizontal, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(backgroundColor)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if selected.isEmpty {
                        Text(.customFields(.documentLinkEmptyLabel))
                    }
                }
            }
        }
        .task {
            await loadSelected()
        }

        .onChange(of: selected) {
            Logger.shared.trace("Selected documents changed: \(selected.count) selected")
            instance.value = .documentLink(selected.map(\.id))
        }
    }
}

private let field = CustomField(id: 9, name: "Custom doc link", dataType: .documentLink)

#Preview {
    @Previewable @State var instance = CustomFieldInstance(field: field, value: .documentLink([]))
    @Previewable
    @StateObject var store = DocumentStore(repository: TransientRepository())

    return NavigationStack {
        Form {
            DocumentLinkView(instance: $instance)

            Section("Instance") {
                Text(String(describing: instance.value))
            }
        }
    }
    .environmentObject(store)
    .task {
        let documents = [
            ("Invoice #123", "file1.pdf"),
            ("Receipt for groceries", "file2.pdf"),
            ("Tax document 2024", "file3.pdf"),
            ("Invoice #456", "file4.pdf"),
            ("Meeting notes", "file5.pdf"),
        ]

        for (title, filename) in documents {
            let protoDoc = ProtoDocument(
                title: title,
                asn: nil,
                documentType: nil,
                correspondent: nil,
                tags: [],
                created: .now,
                storagePath: nil
            )
            try? await store.repository.create(
                document: protoDoc, file: URL(string: "file:///\(filename)")!, filename: filename
            )
        }
    }
}
