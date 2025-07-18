//
//  DocumentEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import Common
import DataModel
import Networking
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

private struct CustomFieldInvalidError: DisplayableError {
    var message: String {
        String(localized: .customFields(.invalidStateHeadline))
    }

    var details: String? {
        String(localized: .customFields(.invalidStateDescription)).stripMarkdown()
    }
}

struct DocumentEditView: View {
    @Environment(\.dismiss) var dismiss

    @ObservedObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController
    @Environment(\.locale) private var locale

    var navPath: Binding<NavigationPath>? = nil

    @State private var initial = true

    @Binding var documentOut: Document
    @State private var document: Document
    private var modified: Bool {
        document != documentOut
    }

    @State private var selectedState = FilterState.default
    @State private var showDeleteConfirmation = false

    @ObservedObject private var appSettings = AppSettings.shared

    @State private var deleted = false

    @State private var suggestions: Suggestions?

    @State var isAsnValid = true

    private var isSaveDisabled: Bool {
        !modified || document.title.isEmpty || !isAsnValid
    }

    private var canEdit: Bool {
        store.permissions.test(.change, for: .document)
    }

    @State private var saving = false

    init(
        store: DocumentStore,
        document: Binding<Document>, navPath: Binding<NavigationPath>? = nil
    ) {
        self.store = store
        _documentOut = document
        _document = State(initialValue: document.wrappedValue)
        self.navPath = navPath
    }

    func doDocumentDelete() {
        Task { @MainActor in
            do {
                Logger.shared.notice("Deleted document from Edit view\("")")
                try await store.deleteDocument(document)
                deleted = true
                let impact = UIImpactFeedbackGenerator(style: .rigid)
                impact.impactOccurred()
                try await Task.sleep(for: .seconds(0.2))
                dismiss()
                if let navPath {
                    Logger.shared.notice("Pop navigation to root\("")")
                    navPath.wrappedValue.popToRoot()
                }
            } catch {
                errorController.push(error: error)
            }
        }
    }

    private func validateCustomFields() throws {
        let instances = [CustomFieldInstance].fromRawEntries(document.customFields.values, customFields: store.customFields, locale: locale)

        if instances.hasInvalidValues {
            throw CustomFieldInvalidError()
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: .localizable(.title)), text: $document.title) {}
                        .clearable($document.title)
                        .disabled(!canEdit)

                    DocumentAsnEditingView(document: $document, isValid: $isAsnValid)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .disabled(!canEdit)

                    DatePicker(String(localized: .localizable(.documentEditCreatedDateLabel)),
                               selection: $document.created.animation(.default),
                               displayedComponents: .date)
                        .disabled(!canEdit)

                    if canEdit, let suggestions, !suggestions.dates.isEmpty {
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
                                document: $document,
                                store: store
                            )
                            .navigationTitle(Text(.localizable(.correspondent)))
                        }) {
                            HStack {
                                Text(.localizable(.correspondent))
                                Spacer()
                                Group {
                                    if let id = document.correspondent {
                                        Text(store.correspondents[id]?.name ?? String(localized: .permissions(.private)))
                                    } else {
                                        Text(.localizable(.correspondentNotAssignedFilter))
                                    }
                                }
                                .foregroundColor(.gray)
                            }
                        }
                        .disabled(!canEdit)
                    }
                    if canEdit {
                        SuggestionView(document: $document,
                                       property: \.correspondent,
                                       elements: store.correspondents,
                                       suggestions: suggestions?.correspondents)
                    }
                }

                Section {
                    HStack { // Prevents problem when applying suggestions
                        NavigationLink(destination: {
                            CommonPickerEdit(
                                manager: DocumentTypeManager.self,
                                document: $document,
                                store: store
                            )
                            .navigationTitle(Text(.localizable(.documentType)))
                        }) {
                            HStack {
                                Text(.localizable(.documentType))
                                Spacer()
                                Group {
                                    if let id = document.documentType {
                                        Text(store.documentTypes[id]?.name ?? String(localized: .permissions(.private)))
                                    } else {
                                        Text(.localizable(.documentTypeNotAssignedFilter))
                                    }
                                }
                                .foregroundColor(.gray)
                            }
                        }
                        .disabled(!canEdit)
                    }

                    if canEdit {
                        SuggestionView(document: $document,
                                       property: \.documentType,
                                       elements: store.documentTypes,
                                       suggestions: suggestions?.documentTypes)
                    }
                }

                Section {
                    HStack { // Prevents problem when applying suggestions
                        NavigationLink(destination: {
                            CommonPickerEdit(
                                manager: StoragePathManager.self,
                                document: $document,
                                store: store
                            )
                            .navigationTitle(Text(.localizable(.storagePath)))
                        }) {
                            HStack {
                                Text(.localizable(.storagePath))
                                Spacer()
                                Group {
                                    if let id = document.storagePath {
                                        Text(store.storagePaths[id]?.name ?? String(localized: .permissions(.private)))
                                    } else {
                                        Text(.localizable(.storagePathNotAssignedFilter))
                                    }
                                }
                                .foregroundColor(.gray)
                            }
                        }
                        .disabled(!canEdit)
                    }

                    if canEdit {
                        SuggestionView(document: $document,
                                       property: \.storagePath,
                                       elements: store.storagePaths,
                                       suggestions: suggestions?.storagePaths)
                    }
                }

                Section {
                    NavigationLink(destination: {
                        DocumentTagEditView(document: $document)
                    }) {
                        if document.tags.isEmpty {
                            Text(.localizable(.numberOfTags(0)))
                        } else {
                            TagsView(tags: document.tags.compactMap { store.tags[$0] })
                                .contentShape(Rectangle())
                        }
                    }
                    .contentShape(Rectangle())
                    .disabled(!canEdit)
                }

                Section {
                    NavigationLink(.permissions(.title)) {
                        PermissionsEditView(object: $document)
                            .disabled(!canEdit)
                    }
                }

                Section {
                    NavigationLink(.customFields(.title)) {
                        CustomFieldsEditView(document: $document)
                            .disabled(!canEdit)
                    }
                }

                Section {
                    Button(action: {
                        if appSettings.documentDeleteConfirmation {
                            showDeleteConfirmation = true
                        } else {
                            doDocumentDelete()
                        }
                    }) {
                        Label(localized: deleted ? .localizable(.documentDeleted) : .localizable(.delete),
                              systemImage: deleted ? "checkmark.circle.fill" : "trash")
                            .contentTransition(.symbolEffect)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(Color.red)
                    .bold()
                    .disabled(!store.permissions.test(.delete, for: .document))

                    .confirmationDialog(String(localized: .localizable(.confirmationPromptTitle)),
                                        isPresented: $showDeleteConfirmation,
                                        titleVisibility: .visible)
                    {
                        Button(String(localized: .localizable(.delete)), role: .destructive) {
                            // @TODO: This will have to become configurable: from places other than DocumentView, this is wrong
                            doDocumentDelete()
                        }
                        Button(String(localized: .localizable(.cancel)), role: .cancel) {}
                    }
                }
                .animation(.default, value: deleted)
            }

            .scrollBounceBehavior(.basedOnSize)

            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    CancelIconButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            do {
                                saving = true
                                try validateCustomFields()
                                documentOut = try await store.updateDocument(document)
                                saving = false
                                dismiss()
                            } catch {
                                errorController.push(error: error)
                                saving = false
                            }
                        }
                    } label: {
                        if !saving {
                            Text(.localizable(.save))
                                .bold()
                        } else {
                            ProgressView()
                        }
                    }
                    .disabled(isSaveDisabled || !canEdit)
                }
            }

            .task {
                do {
                    async let all: Void = store.fetchAll()

                    let refreshDocument: Task<Void, any Error>?
                    if initial {
                        refreshDocument = Task {
                            let doc: Document? = try await store.repository.document(id: document.id)
                            if let doc {
                                // Update both the document and the output binding
                                document = doc
                                documentOut = doc
                            }
                        }
                        initial = false
                    } else {
                        refreshDocument = nil
                    }

                    let suggestions = try await store.repository.suggestions(documentId: document.id)
                    withAnimation {
                        self.suggestions = suggestions
                    }

                    try await all
                    try await refreshDocument?.value
                } catch {
                    Logger.shared.error("Error getting suggestions: \(error)")
                    errorController.push(error: error)
                }
            }
        }
        .presentationDragIndicator(.hidden)

        .errorOverlay(errorController: errorController, offset: 20)
    }
}

#Preview {
    @Previewable @StateObject var store = DocumentStore(repository: TransientRepository())
    @Previewable @StateObject var errorController = ErrorController()
    @Previewable @State var document: Document?
    @Previewable @State var navPath = NavigationPath()

    VStack {
        if document != nil {
            DocumentEditView(store: store, document: Binding($document)!, navPath: $navPath)
                .environmentObject(errorController)
                .environmentObject(store)
        }
    }
    .task {
        do {
            let repository = store.repository as! TransientRepository
            await repository.addUser(User(id: 1, isSuperUser: false, username: "user", groups: []))
            await repository.set(permissionTo: .change, for: .document, to: false)
            try? await repository.login(userId: 1)
            try await store.fetchAll()
            try await store.repository.create(document: ProtoDocument(title: "blubb"),
                                              file: #URL("http://example.com"), filename: "blubb.pdf")
            document = try await store.repository.documents(filter: .default).fetch(limit: 100_000).first { $0.title == "blubb" }
        } catch { print(error) }
    }
}
