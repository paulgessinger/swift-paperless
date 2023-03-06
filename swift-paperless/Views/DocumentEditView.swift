//
//  DocumentEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI

struct DocumentEditView: View {
    @Environment(\.dismiss) var dismiss

    @EnvironmentObject var store: DocumentStore

    @Binding var documentBinding: Document

    @State var document: Document
    @State var modified: Bool = false

    @State var correspondentID: UInt = 0
    @State var documentTypeID: UInt = 0

    init(document: Binding<Document>) {
        self._documentBinding = document
        self._document = State(initialValue: document.wrappedValue)

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
                        Text("SELECT!")
                    }) {
                        TagsView(tags: document.tags.compactMap { store.tags[$0] })
                            .contentShape(Rectangle())
                    }
                    .background(Color.red)
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
                        documentBinding = document
                        // @TODO: Kick off API call to save the document
                        dismiss()
                    }
                    .bold()
                    .disabled(!modified)
                }

            }.onChange(of: document) { _ in
                modified = true
            }.onChange(of: correspondentID) { value in
                document.correspondent = value > 0 ? value : nil
            }.onChange(of: documentTypeID) { value in
                document.documentType = value > 0 ? value : nil
            }
            .task {
                async let _ = await store.fetchAllCorrespondents()
                async let _ = await store.fetchAllDocumentTypes()
            }
        }
    }
}

struct DocumentEditView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore()

    static var document: Document = .init(id: 1689, added: "Hi",
                                          title: "Official ESTA Application Website, U.S. Customs and Border Protection",
                                          documentType: 2, correspondent: 2,
                                          created: Date.now, tags: [75, 66])

    static var previews: some View {
        Group {
            DocumentEditView(document: .constant(document))
        }
        .task { await store.fetchAllTags() }
        .environmentObject(store)
    }
}
