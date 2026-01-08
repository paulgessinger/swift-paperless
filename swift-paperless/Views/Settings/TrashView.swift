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

struct TrashView: View {
  @State private var documents: [Document] = []
  @EnvironmentObject private var store: DocumentStore

  @State private var multiSelection = Set<UInt>()

  private func deleteDocuments(at offsets: IndexSet) {
    // @TODO: Delete documents
    documents.remove(atOffsets: offsets)
  }

  private func restoreDocuments(at offsets: IndexSet) {
    // @TODO: Restore documents
    documents.remove(atOffsets: offsets)
  }

  private func load() async {
    do {
      documents = try await store.repository.trash()
    } catch {
      Logger.shared.error("Error loading trash: \(error)")

    }
  }

  var body: some View {
    List {
      ForEach(documents) { doc in
        Text(doc.title)
      }
      .onDelete(perform: deleteDocuments)
      .swipeActions(edge: .leading, allowsFullSwipe: true) {
        Button(.settings(.trashRestoreButton), systemImage: "arrow.counterclockwise") {}
          .tint(.accentColor)
      }
    }
    .navigationTitle(.settings(.trashTitle))

    .toolbar {
      EditButton()
    }

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
