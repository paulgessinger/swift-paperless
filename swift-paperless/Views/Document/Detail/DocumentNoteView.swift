//
//  DocumentNoteView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 27.07.2024.
//

import DataModel
import os
import SwiftUI

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

        do {
            try await store.addNote(to: document, note: note)
            if let document = try await store.document(id: document.id) {
                self.document = document
            }
            Haptics.shared.notification(.success)
            dismiss()
        } catch {
            Logger.shared.error("Error adding note to document: \(error)")
            errorController.push(error: error)
            saving = false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(.documentMetadata(.notePlaceholder),
                          text: $noteText,
                          axis: .vertical)
                    .focused($focused)

                    .onSubmit {
                        Task { await saveNote() }
                    }
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

struct DocumentNoteView: View {
    @Binding var document: Document

    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController

    @Environment(\.dismiss) private var dismiss

    @State private var adding = false
    @State private var noteToDelete: Document.Note?

    func delete(_ note: Document.Note) {
        Task {
            do {
                try await store.deleteNote(from: document, id: note.id)
                document.notes = document.notes.filter { $0.id != note.id }
            } catch is CancellationError {}
            catch {
                Logger.shared.error("Error deleting note from document: \(error)")
                errorController.push(error: error)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(document.notes) { note in
                        VStack(alignment: .leading) {
                            Text(note.created, style: .date)
                                .font(.caption)
                            Text(note.note)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        .swipeActions(edge: .trailing) {
                            Button(.localizable(.delete), role: .destructive,
                                   action: { delete(note) })
                        }
                    }
                }

                Section {
                    Button {
                        adding = true
                    } label: {
                        Label(.localizable(.add), systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .bold()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .animation(.spring, value: document)

            .scrollBounceBehavior(.basedOnSize)

            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(.documentMetadata(.notes))

            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelIconButton()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        adding = true
                    } label: {
                        Label(.localizable(.add), systemImage: "plus")
                    }
                }
            }

//            .confirmationDialog(unwrapping: $noteToDelete) { _ in
//                String(localized: .documentMetadata(.noteDeleteConfirmation))
//            } actions: {  note  in
//                Button(.localizable(.delete), role: .destructive) {
//                    delete(note.wrappedValue)
//                }
//
//                Button(.localizable(.cancel), role: .cancel) {
//                    noteToDelete = nil
//                }
//            }

            .sheet(isPresented: $adding) {
                CreateNoteView(document: $document)
            }
        }

        .errorOverlay(errorController: errorController, offset: 20)
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
                    DocumentNoteView(document: Binding($document)!)
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
