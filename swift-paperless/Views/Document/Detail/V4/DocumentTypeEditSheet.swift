//
//  DocumentTypeEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 01.04.26.
//

import AppShared
import DataModel
import Networking
import SwiftUI

struct DocumentTypeEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @Environment(DocumentStore.self) private var store

  private struct CreateDocumentTypeView: View {
    @Environment(DocumentStore.self) private var store
    @EnvironmentObject private var errorController: ErrorController
    @Environment(\.dismiss) private var dismiss

    let onCreated: (DocumentType) -> Void

    var body: some View {
      DocumentTypeEditView<ProtoDocumentType>(onSave: { value in
        Task {
          do {
            let documentType = try await store.create(documentType: value)
            onCreated(documentType)
            dismiss()
          } catch {
            errorController.push(error: error)
          }
        }
      })
      .navigationTitle(Text(.app(.documentTypeCreateTitle)))
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  var body: some View {
    SingleSelectPickerSheet(
      viewModel: viewModel,
      storeKeyPath: \.documentTypes,
      keyPath: \.documentType,
      navigationTitle: .app(.documentType),
      listSectionTitle: .app(.documentTypes),
      notAssignedLabel: .app(.documentTypeNotAssignedPicker),
      canCreate: store.permissions.test(.add, for: .documentType),
      suggestions: viewModel.suggestions.documentTypes,
      quickCreate: { name in
        try await store.create(documentType: ProtoDocumentType(name: name))
      },
      createView: { onCreated in
        CreateDocumentTypeView(onCreated: onCreated)
      }
    )
  }
}
