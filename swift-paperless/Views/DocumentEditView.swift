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
    @EnvironmentObject private var errorController: ErrorController

    @State private var document: Document
    @State private var modified: Bool = false

    @State private var selectedState = FilterState()
    @State private var showDeleteConfirmation = false

    @State private var deleted = false

    init(document: Document) {
        self._document = State(initialValue: document)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $document.title) {}
                        .clearable($document.title)
                    DatePicker("Created date", selection: $document.created, displayedComponents: .date)
                }
                Section {
                    NavigationLink(destination: {
                        CommonPickerEdit(
                            manager: CorrespondentManager.self,
                            document: $document,
                            store: store
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
                            manager: DocumentTypeManager.self,
                            document: $document,
                            store: store
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
                        DocumentTagEditView(document: $document)
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
                                        nav.popToRoot()
                                    } catch {
                                        errorController.push(error: error)
                                    }
                                }
                            }
                        }
                    }
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
                                errorController.push(error: error)
                            }
                        }
                        dismiss()
                    }
                    .bold()
                    .disabled(!modified || document.title.isEmpty)
                }
            }
            .onChange(of: document) { _ in
                modified = true
            }

            .task {
                Task.detached {
                    await store.fetchAll()
                }
            }
        }
        .errorOverlay(errorController: errorController)
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
