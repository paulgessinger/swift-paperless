//
//  TrashView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 07.01.26.
//

import DataModel
import Networking
import SwiftUI
import os

//private struct BarButton

struct TrashView: View {
  @State private var documents: [Document] = []
  @EnvironmentObject private var store: DocumentStore
  @State var editMode: EditMode = .inactive
  @EnvironmentObject private var errorController: ErrorController

  @State private var selection = Set<UInt>()
  @State private var showDeleteConfirmation: Bool = false

  private func deleteDocuments(at offsets: IndexSet) {
    deleteDocuments(ids: Set(offsets.compactMap { documents[$0].id }))
  }

  private func deleteDocuments(ids: Set<UInt>) {
    Task {
      do {
        try await store.repository.emptyTrash(documents: Array(ids))
        documents.removeAll(where: { ids.contains($0.id) })
        selection.subtract(ids)
      } catch {
        Logger.shared.error("Error restoring documents: \(error)")
        errorController.push(error: error)
      }
    }
  }

  private func restoreDocuments(ids: Set<UInt>) {
    Task {
      do {
        try await store.repository.restoreTrash(documents: Array(ids))
        documents.removeAll(where: { ids.contains($0.id) })
        selection.subtract(ids)
      } catch {
        Logger.shared.error("Error restoring documents: \(error)")
        errorController.push(error: error)
      }
    }
  }

  private func load() async {
    do {
      documents = try await store.repository.trash()
    } catch {
      Logger.shared.error("Error loading trash: \(error)")
    }
  }

  private var confirmTitle: LocalizedStringResource {
    .settings(.trashConfirmDeleteAction(UInt(selection.count)))
  }

  var body: some View {
    List(selection: $selection) {
      if documents.isEmpty {
        ContentUnavailableView(
          .settings(.trashEmptyTitle), systemImage: "trash",
          description: Text(.settings(.trashEmptyDescription)))
      } else {
        ForEach(documents) { doc in
          Text(doc.title)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
              Button(.settings(.trashRestoreButton), systemImage: "arrow.counterclockwise") {
                restoreDocuments(ids: [doc.id])
              }
              .tint(.accentColor)
            }
        }
        .onDelete { offsets in
          deleteDocuments(ids: Set(offsets.compactMap { documents[$0].id }))
        }
      }
    }

    .animation(.spring, value: documents)
    .animation(.default, value: editMode)
    .navigationTitle(.settings(.trashTitle))

    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if !documents.isEmpty {
          CustomEditButton()
        }
      }

      ToolbarItemGroup(placement: .bottomBar) {
        if editMode.isEditing {
          Button(.settings(.trashRestoreButton), systemImage: "arrow.counterclockwise") {
            restoreDocuments(ids: selection)
          }
          .disabled(selection.isEmpty)

          Button(.localizable(.delete), systemImage: "trash") {
            showDeleteConfirmation = true
          }
          .disabled(selection.isEmpty)
          .confirmationDialog(
            confirmTitle, isPresented: $showDeleteConfirmation, titleVisibility: .visible
          ) {
            Button(.localizable(.delete), role: .destructive) {
              deleteDocuments(ids: selection)
              showDeleteConfirmation = false
            }
            Button(.localizable(.cancel)) {
              selection = Set()
              showDeleteConfirmation = false
            }
          }
        }
      }
    }

    .environment(\.editMode, $editMode)

    .refreshable {
      await load()
    }

    .task {
      await load()
    }
  }
}

#Preview {
  @Previewable @StateObject var store = DocumentStore(repository: TransientRepository())
  @Previewable @StateObject var errorController = ErrorController()
  @Previewable @State var ready = false

  NavigationStack {
    if ready {
      TrashView()
        .environmentObject(store)
        .environmentObject(errorController)
    }
  }
  .task {
    do {
      let repository = store.repository as! TransientRepository
      repository.addUser(User(id: 1, isSuperUser: false, username: "user", groups: []))
      try repository.login(userId: 1)

      let documents = [
        ("Invoice #123", "file1.pdf"),
        ("Receipt for groceries", "file2.pdf"),
        ("Tax document 2024", "file3.pdf"),
        ("Invoice #456", "file4.pdf"),
        ("Meeting notes", "file5.pdf"),
      ]

      for (title, filename) in documents {
        let protoDoc = ProtoDocument(
          title: title,
          asn: nil,
          documentType: nil,
          correspondent: nil,
          tags: [],
          created: .now,
          storagePath: nil
        )
        try? await store.repository.create(
          document: protoDoc, file: URL(string: "file:///\(filename)")!, filename: filename
        )
      }

      try await store.fetchAll()
      let seq = try store.repository.documents(filter: .default)
      let allDocuments = try await seq.fetch(limit: 1000)

      for doc in allDocuments.prefix(4) {
        try await store.repository.delete(document: doc)
      }

      ready = true
    } catch { print(error) }
  }
}
