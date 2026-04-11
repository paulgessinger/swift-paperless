//
//  OwnerEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.04.26.
//

import DataModel
import Networking
import SwiftUI
import os

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
    var expectedVisibilityChange = false
    var expectedEditabilityChange = false

    if let user = store.currentUser {
      expectedVisibilityChange = user.canView(viewModel.document) && !user.canView(document)
      expectedEditabilityChange = user.canChange(viewModel.document) && !user.canChange(document)
    }

    Task {
      do {
        saving = true
        viewModel.document = document
        try await viewModel.updateDocument()
        saving = false
        dismiss()
      } catch let RequestError.unexpectedStatusCode(code, detail) where code == .notFound {
        if expectedVisibilityChange {
          Logger.shared.info("Document update resulted in \(code.rawValue, privacy: .public) as expected due to permission change")
          viewModel.document = document
          dismiss()
        } else {
          let error = RequestError.unexpectedStatusCode(code: code, detail: detail)
          Logger.shared.error("Error updating document: \(error)")
          errorController.push(error: error)
        }
        saving = false
      } catch let RequestError.forbidden(body) {
        if expectedEditabilityChange {
          Logger.shared.info("Document update resulted in forbidden as expected due to permission change")
          viewModel.document = document
          dismiss()
        } else {
          let error = RequestError.forbidden(detail: body)
          Logger.shared.error("Error updating document: \(error)")
          errorController.push(error: error)
        }
        saving = false
      } catch {
        saving = false
        Logger.shared.error("Error updating document: \(error)")
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
