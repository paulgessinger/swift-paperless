//
//  DocumentLinkView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 15.06.25.
//

import DataModel
import Flow
import Networking
import SwiftUI
import os

private struct SearchView: View {
  @Binding var selected: [Document]
  let document: Document?

  @EnvironmentObject private var store: DocumentStore
  @State private var searchText = ""
  @State private var matchingDocuments: [Document] = []

  @State private var searchTask: Task<Void, Never>?
  @Namespace private var namespace

  @State private var searching: Bool = false

  var body: some View {
    List {
      if !selected.isEmpty {
        Section(.customFields(.documentLinkSelectedLabel)) {
          ForEach(selected) { document in
            Button {
              selected = selected.filter { $0.id != document.id }
            } label: {
              HStack {
                Text(document.title)
                  .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark.circle.fill")
                  .contentTransition(.symbolEffect)
              }
            }
          }
        }
      }

      Section {
        let show = matchingDocuments.filter {
          !selected.contains($0) && document != $0
        }
        ForEach(show) { document in
          Button {
            selected.append(document)
          } label: {
            HStack {
              Text(document.title)
                .frame(maxWidth: .infinity, alignment: .leading)
              Image(systemName: "plus.circle")
                .contentTransition(.symbolEffect)
            }
          }
        }
      }

      if !searching {
        Button {
          searching = true
        } label: {
          Label(localized: .customFields(.searchDocumentsButtonLabel), systemImage: "plus")
            .frame(maxWidth: .infinity, alignment: .center)
        }
      }
    }
    .animation(.spring, value: matchingDocuments)
    .animation(.spring, value: selected)
    .animation(.spring, value: searching)
    .searchable(
      text: $searchText,
      isPresented: $searching,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: .customFields(.documentLinkSearchPlaceholder),
    )

    .onChange(of: searchText) {
      guard searchText.count >= 3 else {
        matchingDocuments = []
        return
      }

      searchTask?.cancel()
      searchTask = Task {
        try? await Task.sleep(for: .seconds(0.3))

        do {
          matchingDocuments = try await store.repository.documents(containsTitle: searchText)
        } catch {
          Logger.shared.error("Error searching documents: \(error, privacy: .public)")
        }
      }
    }
  }
}

struct DocumentSelectionView: View {
  let title: String
  @Binding var documentIds: [UInt]
  let document: Document?

  @EnvironmentObject private var store: DocumentStore
  @Environment(\.colorScheme) private var colorScheme

  @State private var selected: [Document] = []

  @State private var initial = true

  private let backgroundColor: Color = .accentColor
  private let foregroundColor: Color = .white

  private func loadSelected() async {
    Logger.shared.trace("Loading documents for \(documentIds.count) document links")
    selected = await withTaskGroup(of: Document?.self, returning: [Document].self) { group in
      for id in documentIds {
        group.addTask {
          do {
            return try await store.repository.document(id: id)
          } catch {
            Logger.shared.error("Error loading document with ID \(id): \(error, privacy: .public)")
            return nil
          }
        }
      }

      var documents = [Document]()

      for await document in group {
        if let document {
          Logger.shared.trace("Loaded document: \(document.title, privacy: .public)")
          documents.append(document)
        }
      }
      return documents
    }
  }

  var body: some View {
    NavigationLink {
      SearchView(selected: $selected, document: document)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(title)
    } label: {
      HStack {
        VStack(alignment: .leading) {
          Text(title)
            .font(.footnote)
            .bold()

          HFlow {
            ForEach(selected) { document in
              HStack {
                Image(systemName: "doc.text")

                Text(document.title)
              }
              .lineLimit(1)
              .padding(5)
              .padding(.horizontal, 10)
              .foregroundStyle(foregroundColor)
              .background {
                RoundedRectangle(cornerRadius: 5)
                  .fill(backgroundColor)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        if selected.isEmpty {
          Text(.customFields(.documentLinkEmptyLabel))
        }
      }
    }

    .task {
      await loadSelected()
    }

    .onChange(of: selected) {
      Logger.shared.trace("Selected documents changed: \(selected.count) selected")
      documentIds = selected.map(\.id)
    }
  }
}

struct DocumentLinkView: View {
  @Binding var instance: CustomFieldInstance
  let document: Document?

  @State private var documentIds = [UInt]()
  @State private var initial = true

  var body: some View {
    // This is here because the `task` modifier triggers too late
    VStack {
      DocumentSelectionView(
        title: instance.field.name,
        documentIds: $documentIds,
        document: document)
    }

    .task {
      guard initial else { return }
      initial = false

      if case .documentLink(let ids) = instance.value {
        documentIds = ids
      } else {
        instance.value = .documentLink([])
      }
    }

    .onChange(of: documentIds) {
      instance.value = .documentLink(documentIds)
    }
  }
}

private let field = CustomField(id: 9, name: "Custom doc link", dataType: .documentLink)

#Preview {
  @Previewable @State var instance = CustomFieldInstance(field: field, value: .documentLink([2]))
  @Previewable
  @StateObject var store = DocumentStore(repository: TransientRepository())
  @Previewable @State var document: Document? = nil

  NavigationStack {
    Form {
      if let document {
        DocumentLinkView(instance: $instance, document: document)
      }

      Section("Instance") {
        Text(String(describing: instance.value))
      }
    }
  }
  .environmentObject(store)
  .task {
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

    if let allDocuments = try? store.repository.documents(filter: .default),
      let doc = try? await allDocuments.fetch(limit: 10000).first
    {
      document = doc
    }
  }
}
