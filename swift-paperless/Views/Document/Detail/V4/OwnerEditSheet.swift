//
//  OwnerEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.04.26.
//

import DataModel
import Networking
import SwiftUI

struct OwnerEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController
  @Environment(\.dismiss) private var dismiss

  @State private var document: Document
  @State private var saving = false

  init(viewModel: DocumentDetailModel) {
    self.viewModel = viewModel
    _document = State(initialValue: viewModel.document)
  }

  private var hasChanges: Bool {
    document.owner != viewModel.document.owner
      || document.permissions != viewModel.document.permissions
  }

  private func save() {
    Task {
      do {
        saving = true
        viewModel.document = document
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
      PermissionsEditView(object: $document)
        .navigationTitle(.permissions(.title))
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
              .disabled(!hasChanges)
            }
          }
        }
    }
    .interactiveDismissDisabled(saving || hasChanges)
  }
}
