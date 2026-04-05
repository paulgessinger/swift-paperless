//
//  DateEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 05.04.26.
//

import DataModel
import Networking
import SwiftUI

struct DateEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController
  @Environment(\.dismiss) private var dismiss

  @State private var date: Date
  @State private var saving = false

  init(viewModel: DocumentDetailModel) {
    self.viewModel = viewModel
    _date = State(initialValue: viewModel.document.created)
  }

  private func save() {
    Task {
      do {
        saving = true
        var document = viewModel.document
        document.created = date
        let updated = try await store.updateDocument(document)
        viewModel.document = updated
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
      ScrollView(.vertical) {
        CustomSection {
          CustomSectionRow {
            DatePicker(
              String(localized: .localizable(.documentEditCreatedDateLabel)),
              selection: $date,
              displayedComponents: .date
            )
          }
        }
      }
      .customSectionBackground(.thickMaterial)
      .scrollBounceBehavior(.basedOnSize)
      .onChange(of: date) {
        save()
      }
      .navigationTitle(.localizable(.documentEditCreatedDateLabel))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CancelIconButton()
        }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          }
        }
      }
    }
    .interactiveDismissDisabled(saving)
  }
}
