//
//  DocumentMetadataView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.07.2024.
//

import os
import SwiftUI

private struct Row<Label: View, Value: View>: View {
    let label: () -> Label
    let value: () -> Value

    var body: some View {
        HStack {
            label()
                .foregroundStyle(.secondary)
            Spacer()
            value()
        }
    }
}

extension Row where Label == Text {
    init(_ label: LocalizedStringKey, value: @escaping () -> Value) {
        self.init(label: { Text(label) }, value: value)
    }
}

extension Row where Value == Text {
    init(label: @escaping () -> Label, value: String) {
        self.init(label: label, value: { Text(value) })
    }
}

extension Row where Label == Text, Value == Text {
    init(_ label: LocalizedStringKey, value: String) {
        self.init(label: { Text(label) }, value: { Text(value) })
    }
}

private struct WideRow<Label: View, Value: View>: View {
    let label: () -> Label
    let value: () -> Value

    var body: some View {
        VStack(alignment: .leading) {
            label()
                .foregroundStyle(.secondary)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension WideRow where Label == Text {
    init(_ label: LocalizedStringKey, value: @escaping () -> Value) {
        self.init(label: { Text(label) }, value: value)
    }
}

extension WideRow where Value == Text {
    init(label: @escaping () -> Label, value: String) {
        self.init(label: label, value: { Text(value) })
    }
}

extension WideRow where Label == Text, Value == Text {
    init(_ label: LocalizedStringKey, value: String) {
        self.init(label: { Text(label) }, value: { Text(value) })
    }
}

private struct Section<Title: View, Content: View>: View {
    @ViewBuilder
    let title: () -> Title

    @ViewBuilder
    let content: () -> Content

    @ScaledMetric(relativeTo: .body) private var spacing = 5.0

    init(@ViewBuilder title: @escaping () -> Title,
         @ViewBuilder content: @escaping () -> Content)
    {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(spacing: spacing) {
            title()
                .font(.headline)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .bottomLeading)
                .padding(.horizontal)
            VStack {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            .background(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(.tertiary)
            )
        }
        .padding()
    }
}

extension Section where Title == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content) {
        title = { EmptyView() }
        self.content = content
    }
}

extension Section where Title == Text {
    init(_ title: LocalizedStringKey,
         @ViewBuilder content: @escaping () -> Content)
    {
        self.init(title: { Text(title) }, content: content)
    }

    init(_ title: String,
         @ViewBuilder content: @escaping () -> Content)
    {
        self.init(title: { Text(title) }, content: content)
    }
}

private struct NoteView: View {
    @Binding var document: Document
    let note: Document.Note

    @State private var showDeleteConfirmation = false
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(note.note)")
                .frame(maxWidth: .infinity, alignment: .leading)

            Label(localized: .localizable(.delete), systemImage: "trash.circle.fill")
                .labelStyle(.iconOnly)
                .symbolRenderingMode(.palette)
                .font(.title)
                .foregroundStyle(.white, .red)
                .onTapGesture {
                    showDeleteConfirmation = true
                }
        }
        .confirmationDialog(String(localized: .documentMetadata(.noteDeleteConfirmation)), isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(String(localized: .localizable(.delete)), role: .destructive) {
                Task {
                    do {
                        try await store.deleteNote(from: document, id: note.id)
                        document.notes = document.notes.filter { $0.id != note.id }
                    } catch {
                        Logger.shared.error("Error deleting note from document: \(error)")
                        errorController.push(error: error)
                    }
                }
            }
            Button(String(localized: .localizable(.cancel)), role: .cancel) {
                showDeleteConfirmation = false
            }
        }
    }
}

struct DocumentMetadataView: View {
    @Binding private var document: Document
    @Binding private var metadata: Metadata?

    @State private var adding = false

    private enum Tabs {
        case metadata
        case notes
    }

    @State private var visibleTab = Tabs.metadata

    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController

    @Environment(\.dismiss) private var dismiss

    init(document: Binding<Document>, metadata: Binding<Metadata?>) {
        _document = document
        _metadata = metadata
    }

    private var loaded: Bool {
        metadata != nil
    }

    private var metadataSection: some View {
        ScrollView(.vertical) {
            Section(.documentMetadata(.title)) {
                if let modified = document.modified {
                    Row(.documentMetadata(.modifiedDate)) {
                        Text(modified, style: .date)
                    }
                }
                if let added = document.added {
                    Divider()
                    Row(.documentMetadata(.addedDate)) {
                        Text(added, style: .date)
                    }
                }

                VStack {
                    if let metadata {
                        Divider()
                        WideRow(.documentMetadata(.mediaFilename),
                                value: metadata.mediaFilename)

                        Divider()
                        WideRow(.documentMetadata(.originalFilename),
                                value: metadata.originalFilename)

                        Divider()
                        WideRow(.documentMetadata(.originalChecksum)) {
                            Text(metadata.originalChecksum)
                                .italic()
                        }

                        Divider()
                        Row(.documentMetadata(.originalFilesize)) {
                            Text(metadata.originalSize.formatted(.byteCount(style: .file)))
                        }

                        Divider()
                        Row(.documentMetadata(.originalMimeType),
                            value: metadata.originalMimeType)

                        if let archiveChecksum = metadata.archiveChecksum {
                            Divider()
                            WideRow(.documentMetadata(.archiveChecksum)) {
                                Text(archiveChecksum)
                                    .italic()
                            }
                        }

                        if let archiveSize = metadata.archiveSize {
                            Divider()
                            Row(.documentMetadata(.archiveFilesize)) {
                                Text(archiveSize.formatted(.byteCount(style: .file)))
                            }
                        }
                    } else {
                        ProgressView()
                            .padding()
                    }
                }
                .animation(.spring.delay(0.2), value: loaded)
            }
            .animation(.spring, value: loaded)

            .padding(.top)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var notesSection: some View {
        ScrollView(.vertical) {
            Section {
                HStack(alignment: .bottom) {
                    Text(.documentMetadata(.notes))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Label(localized: .localizable(.add), systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly)
                        .symbolRenderingMode(.palette)
                        .font(.title)
                        .foregroundStyle(.primary, .tertiary)
                        .onTapGesture {
                            adding = true
                        }
                }
            } content: {
                if !document.notes.isEmpty {
                    ForEach(document.notes) { note in
                        NoteView(document: $document,
                                 note: note)
                        if note != document.notes.last {
                            Divider()
                                .padding(.bottom)
                        }
                    }
                } else {
                    VStack {
                        Text(.documentMetadata(.notesNone))
                            .italic()
                        Button(String(localized: .documentMetadata(.addNote))) {
                            adding = true
                        }
                        .bold()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            .padding(.top)

            .animation(.spring, value: document)
            .animation(.spring, value: adding)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $visibleTab) {
                metadataSection
                    .tag(Tabs.metadata)
                notesSection
                    .tag(Tabs.notes)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Label(localized: .localizable(.back), systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, .thickMaterial)
                        .font(.title)
                        .onTapGesture {
                            dismiss()
                        }
                        .padding(.top)
                }

                ToolbarItem(placement: .principal) {
                    Picker(selection: $visibleTab) {
                        Text(.documentMetadata(.title))
                            .tag(Tabs.metadata)
                        Text(.documentMetadata(.notes))
                            .tag(Tabs.notes)
                    } label: {
                        Text("tab")
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .padding(.top)
                }
            }

            .sheet(isPresented: $adding) {
                CreateNoteView(document: $document)
            }

            .errorOverlay(errorController: errorController)

            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CreateNoteView: View {
    @Binding var document: Document

    @State private var noteText: String = ""
    @State private var saving = false

    @FocusState private var focused: Bool

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController

    private func saveNote() async {
        guard !noteText.isEmpty else { return }

        let note = ProtoDocument.Note(note: noteText)
        saving = true
        defer { saving = false }

        do {
            try await store.addNote(to: document, note: note)
            if let document = try await store.document(id: document.id) {
                self.document = document
            }
            noteText = ""
            dismiss()
        } catch {
            Logger.shared.error("Error adding note to document: \(error)")
            errorController.push(error: error)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(.documentMetadata(.notePlaceholder),
                          text: $noteText,
                          axis: .vertical)
                    .focused($focused)
            }

            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.localizable(.cancel), role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if !saving {
                        Button(.localizable(.add)) {
                            Task { await saveNote() }
                        }
                        .bold()
                        .disabled(noteText.isEmpty)
                    } else {
                        ProgressView()
                    }
                }
            }

            .navigationTitle(.documentMetadata(.noteCreate))
            .navigationBarTitleDisplayMode(.inline)
        }
        .errorOverlay(errorController: errorController, offset: 20)
        .task {
            focused = true
        }
    }
}

// - MARK: Preview

private struct PreviewHelper: View {
    @StateObject var store = DocumentStore(repository: PreviewRepository(downloadDelay: 3.0))
    @StateObject var errorController = ErrorController()

    @State var document: Document?
    @State var metadata: Metadata?

    var body: some View {
        NavigationStack {
            VStack {
                if document != nil {
                    DocumentMetadataView(document: Binding($document)!, metadata: $metadata)
                }
            }
            .task {
                document = try? await store.document(id: 1)
                if let document {
                    metadata = try? await store.repository.metadata(documentId: document.id)
                }
            }
        }
        .environmentObject(store)
        .environmentObject(errorController)

        .task {
            try? await store.fetchAll()
        }
    }
}

#Preview {
    PreviewHelper()
}
