//
//  DocumentTypeEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 01.04.26.
//

import DataModel
import Networking
import SwiftUI

struct DocumentTypeEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore

  private struct CreateDocumentTypeView: View {
    @EnvironmentObject private var store: DocumentStore
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
      .navigationTitle(Text(.localizable(.documentTypeCreateTitle)))
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  var body: some View {
    SingleSelectPickerSheet(
      viewModel: viewModel,
      allItems: { Array(store.documentTypes.values) },
      keyPath: \.documentType,
      navigationTitle: .localizable(.documentType),
      listSectionTitle: .localizable(.documentTypes),
      notAssignedLabel: .localizable(.documentTypeNotAssignedPicker),
      canCreate: store.permissions.test(.add, for: .documentType),
      suggestions: viewModel.suggestions.documentTypes,
      createView: { onCreated in
        CreateDocumentTypeView(onCreated: onCreated)
      }
    )
  }
}
