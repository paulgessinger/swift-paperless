//
//  CustomFieldsEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.04.26.
//

import DataModel
import Networking
import SwiftUI

struct CustomFieldsEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale

  @State private var document: Document
  @State private var saving = false

  init(viewModel: DocumentDetailModel) {
    self.viewModel = viewModel
    _document = State(initialValue: viewModel.document)
  }

  private var hasChanges: Bool {
    document.customFields != viewModel.document.customFields
  }

  private var hasInvalidFields: Bool {
    let instances = [CustomFieldInstance].fromRawEntries(
      document.customFields.values, customFields: store.customFields, locale: locale)
    return instances.hasInvalidValues
  }

  private func save() {
    Task {
      do {
        saving = true
        viewModel.document.customFields = document.customFields
        try await viewModel.updateDocument()
        saving = false
        dismiss()
      } catch {
        saving = false
        errorController.push(error: error)
      }
    }
  }

  var body: some View {
    NavigationStack {
      CustomFieldsEditView(document: $document)
        .navigationTitle(.customFields(.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            CancelIconButton()
          }
          ToolbarItem(placement: .confirmationAction) {
            if saving {
              ProgressView()
            } else {
              SaveButton {
                save()
              }
              .disabled(!hasChanges || hasInvalidFields)
            }
          }
        }
    }
    .interactiveDismissDisabled(saving || hasChanges)
  }
}
