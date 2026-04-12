//
//  DocumentNoteView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 27.07.2024.
//

import DataModel
import Networking
import SwiftUI
import os

private struct CreateNoteView: View {
  @Binding var document: Document
  @Binding var notes: [Document.Note]

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
      // We have no way to only get the new note here
      notes = try await store.notes(for: document)
      document.notes.count = notes.count
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
        TextField(
          .documentMetadata(.notePlaceholder),
          text: $noteText,
          axis: .vertical
        )
        .focused($focused)

        .onSubmit {
          Task { await saveNote() }
        }
      }

      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CancelIconButton()
        }

        ToolbarItem(placement: .confirmationAction) {
          SaveButton(action: {
            Task { await saveNote() }
          })
          .disabled(noteText.isEmpty || saving)
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

  @State private var notes: [Document.Note] = []

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController

  @Environment(\.dismiss) private var dismiss

  @State private var adding = false
  @State private var noteToDelete: Document.Note?

  private func delete(_ note: Document.Note) {
    Task {
      do {
        try await store.deleteNote(from: document, id: note.id)
        notes = notes.filter { $0.id != note.id }
        document.notes.count = notes.count
      } catch let error where !error.isCancellationError {
        Logger.shared.error("Error deleting note from document: \(error)")
        errorController.push(error: error)
      }
    }
  }

  private func loadNotes() async {
    do {
      notes = try await store.notes(for: document)
    } catch let error where error.isCancellationError {} catch {
      Logger.shared.error("Error loading notes for document: \(error)")
      errorController.push(error: error)
    }
  }

  private var canViewNotes: Bool {
    store.permissions.test(.view, for: .note)
  }

  var body: some View {
    NavigationStack {
      VStack {
        if !canViewNotes {
          Form {
            ContentUnavailableView(
              String(localized: .permissions(.noViewPermissionsDisplayTitle)),
              systemImage: "lock.fill",
              description: Text(.permissions(.noViewPermissionsNotes)))
          }
        } else if notes.isEmpty {
          Form {
            ContentUnavailableView {
              Label(
                LocalizedStringResource("notesEmptyTitle", table: "DocumentMetadata"),
                systemImage: "note.text"
              )
            } description: {
              Text(LocalizedStringResource("notesEmptyDescription", table: "DocumentMetadata"))
            }
          }
        } else {
          List {
            Section {
              ForEach(notes) { note in
                VStack(alignment: .leading) {
                  HStack {
                    Text(note.created, style: .date)
                    if let user = note.user, !user.username.isEmpty {
                      Spacer()
                      Text(user.username)
                    }
                  }
                  .font(.caption)
                  Text(note.note)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                .if(store.permissions.test(.delete, for: .note)) {
                  $0.swipeActions(edge: .trailing) {
                    Button(
                      .localizable(.delete), role: .destructive,
                      action: { delete(note) })
                  }
                }
              }
            }
          }
        }
      }
      .animation(.spring, value: document)

      .navigationBarTitleDisplayMode(.inline)
      .navigationTitle(.documentMetadata(.notes))

      .scrollBounceBehavior(.basedOnSize)

      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CancelIconButton()
        }

        if canViewNotes {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              adding = true
            } label: {
              Label(.localizable(.add), systemImage: "plus")
            }
            .disabled(!store.permissions.test(.add, for: .note))
          }
        }
      }

      .refreshable {
        Task { await loadNotes() }
      }

      .sheet(isPresented: $adding) {
        CreateNoteView(document: $document, notes: $notes)
      }
    }

    .errorOverlay(errorController: errorController, offset: 20)

    .task {
      guard canViewNotes else { return }
      await loadNotes()
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
