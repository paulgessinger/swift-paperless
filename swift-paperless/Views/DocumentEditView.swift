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

    @Binding private var documentBinding: Document

    @State private var document: Document
    @State private var modified: Bool = false

    @State private var correspondentID: UInt = 0
    @State private var documentTypeID: UInt = 0

    @State private var selectedTags = FilterState.Tag.notAssigned

    init(document: Binding<Document>) {
        self._documentBinding = document
        self._document = State(initialValue: document.wrappedValue)

        if !self.document.tags.isEmpty {
            self._selectedTags = State(initialValue: .only(ids: self.document.tags))
        }

        if let c = document.correspondent.wrappedValue {
            self._correspondentID = State(initialValue: c)
        }

        if let d = document.documentType.wrappedValue {
            self._documentTypeID = State(initialValue: d)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $document.title) {}
                    DatePicker("Created date", selection: $document.created, displayedComponents: .date)
                }
                Section {
                    Picker("Correspondent", selection: $correspondentID) {
                        Text("None").tag(UInt(0))
                        ForEach(store.correspondents.sorted { $0.value.name < $1.value.name }, id: \.value.id) { _, c in
                            Text("\(c.name)").tag(c.id)
                        }
                    }
                    Picker("Document type", selection: $documentTypeID) {
                        Text("None").tag(UInt(0))
                        ForEach(store.documentTypes.sorted { $0.value.name < $1.value.name }, id: \.value.id) { _, c in
                            Text("\(c.name)").tag(c.id)
                        }
                    }

                    NavigationLink(destination: {
                        TagSelectionView(tags: store.tags,
                                         selectedTags: $selectedTags,
                                         filterMode: false)
                            .navigationTitle("Tags")
                    }) {
                        TagsView(tags: document.tags.compactMap { store.tags[$0] })
                            .contentShape(Rectangle())
                    }
                    .contentShape(Rectangle())
                }
            }.toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        print(document)
                        documentBinding = document
                        // @TODO: Kick off API call to save the document
                        dismiss()
                    }
                    .bold()
                    .disabled(!modified)
                }
            }
            .onChange(of: document) { _ in
                modified = true
            }
            .onChange(of: correspondentID) { value in
                document.correspondent = value > 0 ? value : nil
            }
            .onChange(of: documentTypeID) { value in
                document.documentType = value > 0 ? value : nil
            }
            .onChange(of: selectedTags) { value in
                print("on change")
                switch value {
                case .any:
                    print("Invalid selected tags .any: this should not happen")
                case .notAssigned:
                    document.tags = []
                case .only(let ids):
                    document.tags = ids
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
    @StateObject static var store = DocumentStore()

    static var document: Document = .init(id: 1689, added: "Hi",
                                          title: "Official ESTA Application Website, U.S. Customs and Border Protection",
                                          documentType: 2, correspondent: 2,
                                          created: Date.now, tags: [75, 66, 65, 64])

    static var previews: some View {
        Group {
            DocumentEditView(document: .constant(document))
        }
        .task { await store.fetchAllTags() }
        .environmentObject(store)
    }
}
