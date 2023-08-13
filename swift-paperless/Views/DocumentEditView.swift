//
//  DocumentEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import os
import SwiftUI

private struct SuggestionView<Element>: View
    where Element: Named, Element: Identifiable, Element.ID == UInt
{
    @Binding var document: Document
    let property: WritableKeyPath<Document, UInt?>
    let elements: [UInt: Element]
    let suggestions: [UInt]?

    var body: some View {
        if let suggestions {
            let selected = suggestions
                .filter { $0 != document[keyPath: property] }
                .compactMap { elements[$0] }
            if !selected.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(selected, id: \.id) { element in
                            Text("\(element.name)")
                                .foregroundColor(.accentColor)
                                .underline()
                                .font(.footnote)
                                .onTapGesture {
                                    Task {
                                        withAnimation {
                                            document[keyPath: property] = element.id
                                        }
                                    }
                                }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

struct DocumentEditView: View {
    @Environment(\.dismiss) var dismiss

    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController

    var navPath: Binding<NavigationPath>? = nil

    @Binding var documentOut: Document
    @State private var document: Document
    private var modified: Bool {
        document != documentOut
    }

    @State private var selectedState = FilterState()
    @State private var showDeleteConfirmation = false

    @AppStorage(SettingsKeys.documentDeleteConfirmation)
    var documentDeleteConfirmation: Bool = true

    @State private var deleted = false

    @State private var suggestions: Suggestions?

    private var asn: Binding<String> {
        .init(get: {
            if let asn = document.asn {
                return "\(asn)"
            } else {
                return ""
            }
        }, set: { document.asn = UInt($0) })
    }

    func asnPlusOne() async {
        let nextAsn = await store.repository.nextAsn()
        withAnimation {
            document.asn = nextAsn
        }
    }

    init(document: Binding<Document>, navPath: Binding<NavigationPath>? = nil) {
        self._documentOut = document
        self._document = State(initialValue: document.wrappedValue)
        self.navPath = navPath
    }

    func doDocumentDelete() {
        DispatchQueue.main.async {
            Task {
                do {
                    Logger.shared.trace("Deleted document from Edit view")
                    try await self.store.deleteDocument(self.document)
                    self.deleted = true
                    let impact = UIImpactFeedbackGenerator(style: .rigid)
                    impact.impactOccurred()
                    try await Task.sleep(for: .seconds(0.2))
                    self.dismiss()
                    if let navPath {
                        Logger.shared.trace("Pop navigation to root")
                        navPath.wrappedValue.popToRoot()
                    }
                } catch {
                    self.errorController.push(error: error)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: self.$document.title) {}
                        .clearable(self.$document.title)

                    TextField("ASN", text: asn)
                        .keyboardType(.numberPad)
                        .overlay(alignment: .trailing) {
                            if document.asn == nil {
                                Button("+1") { Task { await asnPlusOne() }}
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .fill(Color.accentColor))
                                    .foregroundColor(.white)
                            }
                        }

                    DatePicker("Created date",
                               selection: self.$document.created.animation(.default),
                               displayedComponents: .date)

                    if let suggestions, !suggestions.dates.isEmpty {
                        let valid = suggestions.dates.filter { $0.formatted(date: .abbreviated, time: .omitted) != document.created.formatted(date: .abbreviated, time: .omitted) }
                        if !valid.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(valid, id: \.self) { date in
                                        Text(date, style: .date)
                                            .foregroundColor(.accentColor)
                                            .font(.footnote)
                                            .underline()
                                            .onTapGesture {
                                                Task {
                                                    withAnimation {
                                                        document.created = date
                                                    }
                                                }
                                            }
                                    }
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                }

                Section {
                    HStack { // Prevents problem when applying suggestions
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
                    }
                    SuggestionView(document: $document,
                                   property: \.correspondent,
                                   elements: store.correspondents,
                                   suggestions: suggestions?.correspondents)
                }

                Section {
                    HStack { // Prevents problem when applying suggestions
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
                    }

                    SuggestionView(document: $document,
                                   property: \.documentType,
                                   elements: store.documentTypes,
                                   suggestions: suggestions?.documentTypes)
                }

                Section {
                    HStack { // Prevents problem when applying suggestions
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
                    }

                    SuggestionView(document: $document,
                                   property: \.storagePath,
                                   elements: store.storagePaths,
                                   suggestions: suggestions?.storagePaths)
                }

                Section {
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
                        if documentDeleteConfirmation {
                            self.showDeleteConfirmation = true
                        } else {
                            doDocumentDelete()
                        }
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
                            // @TODO: This will have to become configurable: from places other than DocumentView, this is wrong
                            doDocumentDelete()
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

            .task {
                Task.detached {
                    await gather([
                        self.store.fetchAll,
                        {
                            if await suggestions == nil {
                                let suggestions = await store.repository.suggestions(documentId: document.id)
                                await MainActor.run {
                                    withAnimation {
                                        self.suggestions = suggestions
                                    }
                                }
                            }
                        }
                    ])
                }
            }
        }
        .errorOverlay(errorController: self.errorController)
    }
}

private struct PreviewHelper: View {
    @EnvironmentObject var store: DocumentStore
    @State var document: Document?
    @State var navPath = NavigationPath()

    var body: some View {
        VStack {
            if self.document != nil {
                DocumentEditView(document: Binding(unwrapping: $document)!, navPath: $navPath)
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
