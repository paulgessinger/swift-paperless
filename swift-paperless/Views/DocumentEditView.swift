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

        var filter = FilterState()

        filter.tags = .notAssigned
        filter.correspondent = .notAssigned
        filter.documentType = .notAssigned

        if !self.document.tags.isEmpty {
            filter.tags = .only(ids: self.document.tags)
        }

        if let corr = self.document.correspondent {
            filter.correspondent = .only(id: corr)
        }

        if let dt = self.document.documentType {
            filter.documentType = .only(id: dt)
        }

        self._selectedState = State(initialValue: filter)
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
                        CommonPicker(
                            selection: $selectedState.correspondent,
                            elements: store.correspondents.sorted {
                                $0.value.name < $1.value.name
                            }.map { ($0.value.id, $0.value.name) },
                            filterMode: false
                        )
                    }) {
                        HStack {
                            Text("Correspondent")
                            Spacer()
                            Group { () -> Text in
                                var label = "None"
                                switch selectedState.correspondent {
                                case .any:
                                    print("Selected 'any' correspondent, this should not happen")
                                case .notAssigned:
                                    break
                                case .only(let id):
                                    label = store.correspondents[id]?.name ?? "None"
                                }
                                return Text(label)
                                    .foregroundColor(.gray)
                            }
                        }
                    }

                    NavigationLink(destination: {
                        CommonPicker(
                            selection: $selectedState.documentType,
                            elements: store.documentTypes.sorted {
                                $0.value.name < $1.value.name
                            }.map { ($0.value.id, $0.value.name) },
                            filterMode: false
                        )
                    }) {
                        HStack {
                            Text("Document type")
                            Spacer()
                            Group { () -> Text in
                                var label = "None"
                                switch selectedState.documentType {
                                case .any:
                                    print("Selected 'any' document type, this should not happen")
                                case .notAssigned:
                                    break
                                case .only(let id):
                                    label = store.documentTypes[id]?.name ?? "None"
                                }
                                return Text(label)
                                    .foregroundColor(.gray)
                            }
                        }
                    }

                    NavigationLink(destination: {
                        TagSelectionView(tags: store.tags,
                                         selectedTags: $selectedState.tags,
                                         filterMode: false)
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
            .onChange(of: selectedState) { value in
                switch value.tags {
                case .any:
                    print("Invalid selected tags .any: this should not happen")
                case .notAssigned:
                    document.tags = []
                case .only(let ids):
                    document.tags = ids
                }

                switch value.correspondent {
                case .any:
                    print("Invalid selected correspondent .any: this should not happen")
                case .notAssigned:
                    document.correspondent = nil
                case .only(let ids):
                    document.correspondent = ids
                }

                switch value.documentType {
                case .any:
                    print("Invalid selected document type .any: this should not happen")
                case .notAssigned:
                    document.documentType = nil
                case .only(let ids):
                    document.documentType = ids
                }
            }

            .task {
                async let _ = await store.fetchAllCorrespondents()
                async let _ = await store.fetchAllDocumentTypes()
                async let _ = await store.fetchAllTags()
            }
        }
    }
}

struct DocumentEditView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: NullRepository())

    static var document: Document = .init(id: 1689,
                                          title: "Official ESTA Application Website, U.S. Customs and Border Protection",
                                          documentType: 2, correspondent: 2,
                                          created: Date.now, tags: [75, 66, 65, 64])

    static var previews: some View {
        Group {
            DocumentEditView(document: document)
        }
        .task { await store.fetchAllTags() }
        .environmentObject(store)
    }
}
