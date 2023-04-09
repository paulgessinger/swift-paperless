//
//  DocumentEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI

struct DocumentEditView: View {
    @Environment(\.dismiss) var dismiss

    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var nav: NavigationCoordinator

    @State private var document: Document
    @State private var modified: Bool = false

    @State private var selectedState = FilterState()
    @State private var showDeleteConfirmation = false

    @State private var error = ""
    @State private var showError = false
    @State private var deleted = false

    init(document: Document) {
        self._document = State(initialValue: document)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $document.title) {}
                    DatePicker("Created date", selection: $document.created, displayedComponents: .date)
                }
                Section {
                    NavigationLink(destination: {
                        CommonPickerEdit(
                            Correspondent.self,
                            document: $document
                        )
                    }) {
                        HStack {
                            Text("Correspondent")
                            Spacer()
                            Group {
                                if let id = document.correspondent {
                                    Text(store.correspondents[id]?.name ?? "ERROR")
                                } else {
                                    Text("None")
                                }
                            }
                            .foregroundColor(.gray)
                        }
                    }

                    NavigationLink(destination: {
                        CommonPickerEdit(
                            DocumentType.self,
                            document: $document
                        )
                    }) {
                        HStack {
                            Text("Document type")
                            Spacer()
                            Group {
                                if let id = document.documentType {
                                    Text(store.documentTypes[id]?.name ?? "ERROR")
                                } else {
                                    Text("None")
                                }
                            }
                            .foregroundColor(.gray)
                        }
                    }
//
                    NavigationLink(destination: {
                        TagEditView(document: $document)
                            .navigationTitle("Tags")
                    }) {
                        if document.tags.isEmpty {
                            Text("No tags")
                        } else {
                            TagsView(tags: document.tags.compactMap { store.tags[$0] })
                                .contentShape(Rectangle())
                        }
                    }
                    .contentShape(Rectangle())
                }

                Section {
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack {
                            Spacer()
                            if !deleted {
                                Text("Delete")
                            } else {
                                HStack {
                                    Text("Deleted")
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            Spacer()
                        }
                    }
                    .foregroundColor(Color.red)
                    .bold()

                    .alert("Delete document \(document.title)", isPresented: $showDeleteConfirmation) {
                        Button("Cancel", role: .cancel) {}
                        Button("Delete", role: .destructive) {
                            DispatchQueue.main.async {
                                Task {
                                    do {
                                        try await store.deleteDocument(document)
                                        deleted = true
                                        let impact = UIImpactFeedbackGenerator(style: .rigid)
                                        impact.impactOccurred()
                                        try await Task.sleep(for: .seconds(0.2))
                                        dismiss()
//                                    do {
//                                        try await Task.sleep(for: .seconds(0.2))
//                                    } catch {}
                                        nav.popToRoot()
                                    } catch {
                                        self.error = "\(error)"
                                        showError = true
                                    }
                                }
                            }
                        }
                    }

                    .alert(error, isPresented: $showError) {}
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            do {
                                try await store.updateDocument(document)
                            } catch {
                                print(error)
                                fatalError("Failed saving")
                            }
                        }
                        dismiss()
                    }
                    .bold()
                    .disabled(!modified)
                }
            }
            .onChange(of: document) { _ in
                modified = true
            }

            .task {
                async let _ = await store.fetchAllCorrespondents()
                async let _ = await store.fetchAllDocumentTypes()
                async let _ = await store.fetchAllTags()
            }
        }
    }
}

private struct PreviewHelper: View {
    @EnvironmentObject var store: DocumentStore
    @State var document: Document?

    var body: some View {
        VStack {
            if let document = document {
                DocumentEditView(document: document)
            }
        }
        .task {
            document = await store.document(id: 1)
        }
    }
}

struct DocumentEditView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        PreviewHelper()
            .environmentObject(store)
    }
}
