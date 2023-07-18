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

    @Binding var documentOut: Document
    @State private var document: Document
    @State private var modified: Bool = false

    @State private var selectedState = FilterState()
    @State private var showDeleteConfirmation = false

    @State private var deleted = false

    init(document: Binding<Document>) {
        self._documentOut = document
        self._document = State(initialValue: document.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: self.$document.title) {}
                        .clearable(self.$document.title)
                    DatePicker("Created date", selection: self.$document.created, displayedComponents: .date)
                }
                Section {
                    NavigationLink(destination: {
                        CommonPickerEdit(
                            manager: CorrespondentManager.self,
                            document: self.$document,
                            store: self.store
                        )
                        .navigationTitle("Correspondent")
                    }) {
                        HStack {
                            Text("Correspondent")
                            Spacer()
                            Group {
                                if let id = document.correspondent {
                                    Text(self.store.correspondents[id]?.name ?? "ERROR")
                                } else {
                                    Text(LocalizedStrings.Filter.Correspondent.notAssignedFilter)
                                }
                            }
                            .foregroundColor(.gray)
                        }
                    }

                    NavigationLink(destination: {
                        CommonPickerEdit(
                            manager: DocumentTypeManager.self,
                            document: self.$document,
                            store: self.store
                        )
                        .navigationTitle("Document type")
                    }) {
                        HStack {
                            Text("Document type")
                            Spacer()
                            Group {
                                if let id = document.documentType {
                                    Text(self.store.documentTypes[id]?.name ?? "ERROR")
                                } else {
                                    Text(LocalizedStrings.Filter.DocumentType.notAssignedFilter)
                                }
                            }
                            .foregroundColor(.gray)
                        }
                    }

                    NavigationLink(destination: {
                        CommonPickerEdit(
                            manager: StoragePathManager.self,
                            document: self.$document,
                            store: self.store
                        )
                        .navigationTitle("Storage path")
                    }) {
                        HStack {
                            Text("Storage path")
                            Spacer()
                            Group {
                                if let id = document.storagePath {
                                    Text(self.store.storagePaths[id]?.name ?? "ERROR")
                                } else {
                                    Text(LocalizedStrings.Filter.StoragePath.notAssignedFilter)
                                }
                            }
                            .foregroundColor(.gray)
                        }
                    }

                    NavigationLink(destination: {
                        DocumentTagEditView(document: self.$document)
                    }) {
                        if self.document.tags.isEmpty {
                            Text("\(0) tag(s)")
                        } else {
                            TagsView(tags: self.document.tags.compactMap { self.store.tags[$0] })
                                .contentShape(Rectangle())
                        }
                    }
                    .contentShape(Rectangle())
                }

                Section {
                    Button(action: {
                        self.showDeleteConfirmation = true
                    }) {
                        HStack {
                            Spacer()
                            if !self.deleted {
                                Text(String(localized: "Delete", comment: "Delete document"))
                            } else {
                                HStack {
                                    Text(String(localized: "Deleted", comment: "Document deleted"))
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            Spacer()
                        }
                    }
                    .foregroundColor(Color.red)
                    .bold()

                    .confirmationDialog(String(localized: "Are you sure?",
                                               comment: "Document delete confirmation"),
                                        isPresented: self.$showDeleteConfirmation,
                                        titleVisibility: .visible)
                    {
                        Button("Delete", role: .destructive) {
                            DispatchQueue.main.async {
                                Task {
                                    do {
                                        try await self.store.deleteDocument(self.document)
                                        self.deleted = true
                                        let impact = UIImpactFeedbackGenerator(style: .rigid)
                                        impact.impactOccurred()
                                        try await Task.sleep(for: .seconds(0.2))
                                        self.dismiss()
                                        self.nav.popToRoot()
                                    } catch {
                                        self.errorController.push(error: error)
                                    }
                                }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", role: .cancel) {
                        self.dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Save", comment: "Save document")) {
                        Task {
                            let copy = document
                            documentOut = document
                            do {
                                try await self.store.updateDocument(self.document)
                            } catch {
                                self.errorController.push(error: error)
                                documentOut = copy
                            }
                        }
                        self.dismiss()
                    }
                    .bold()
                    .disabled(!self.modified || self.document.title.isEmpty)
                }
            }

            .onChange(of: self.document) { _ in
                self.modified = true
            }

            .task {
                Task.detached {
                    await self.store.fetchAll()
                }
            }
        }
        .errorOverlay(errorController: self.errorController)
    }
}

private struct PreviewHelper: View {
    @EnvironmentObject var store: DocumentStore
    @State var document: Document?

    var body: some View {
        VStack {
            if self.document != nil {
                DocumentEditView(document: Binding(unwrapping: $document)!)
            }
        }
        .task {
            self.document = await self.store.document(id: 1)
            guard self.document != nil else {
                fatalError()
            }
        }
    }
}

struct DocumentEditView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())
    @StateObject static var errorController = ErrorController()

    static var previews: some View {
        PreviewHelper()
            .environmentObject(store)
            .environmentObject(errorController)
    }
}
