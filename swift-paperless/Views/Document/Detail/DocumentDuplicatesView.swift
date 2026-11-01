//
//  DocumentDuplicatesView.swift
//  swift-paperless
//

import AppShared
import AppViews
import DataModel
import SwiftUI

/// Other documents with the same file content. Trashed ones are listed but
/// can't be opened.
struct DocumentDuplicatesView: View {
  let duplicates: [DocumentDuplicate]
  let open: (UInt) -> Void

  private func title(of duplicate: DocumentDuplicate) -> String {
    duplicate.title.isEmpty ? "#\(duplicate.id)" : duplicate.title
  }

  @ViewBuilder
  private func row(_ duplicate: DocumentDuplicate) -> some View {
    if duplicate.deletedAt != nil {
      LabeledContent(title(of: duplicate)) {
        Text(.documentMetadata(.duplicateInTrash))
      }
      .foregroundStyle(.secondary)
    } else {
      Button {
        open(duplicate.id)
      } label: {
        LabeledContent(title(of: duplicate)) {
          HStack {
            Text(verbatim: "#\(duplicate.id)")
            Image(systemName: "chevron.right")
              .font(.footnote)
              .fontWeight(.semibold)
              .foregroundStyle(.tertiary)
          }
        }
      }
      .tint(.primary)
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          ForEach(duplicates) { row($0) }
        } footer: {
          Text(.documentMetadata(.duplicatesExplanation))
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .navigationTitle(.documentMetadata(.duplicates))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CancelIconButton()
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

// - MARK: Preview

#Preview {
  Color.clear.sheet(isPresented: .constant(true)) {
    DocumentDuplicatesView(
      duplicates: [
        DocumentDuplicate(id: 28, title: "Quarterly Statement"),
        DocumentDuplicate(id: 31, title: ""),
        DocumentDuplicate(id: 12, title: "Scan", deletedAt: .now),
      ],
      open: { _ in }
    )
  }
}
