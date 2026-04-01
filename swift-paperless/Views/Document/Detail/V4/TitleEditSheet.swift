//
//  TitleEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 01.04.26.
//

import DataModel
import Networking
import SwiftUI

struct TitleEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController
  @Environment(\.dismiss) private var dismiss

  @State private var title = ""
  @State private var saving = false
  @FocusState private var focused: Bool

  private func save() {
    Task {
      do {
        saving = true
        var document = viewModel.document
        document.title = title
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
            TextField(
              String(localized: .localizable(.documentEditTitleLabel)),
              text: $title,
              axis: .vertical
            )
            .focused($focused)
          }
        }
      }
      .customSectionBackground(.thickMaterial)
      .scrollBounceBehavior(.basedOnSize)
      .navigationTitle(.localizable(.title))
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
            .disabled(
              title.trimmingCharacters(in: .whitespaces).isEmpty
                || title == viewModel.document.title)
          }
        }
      }
    }
    .interactiveDismissDisabled(saving || title != viewModel.document.title)
    .onAppear {
      title = viewModel.document.title
      focused = true
    }
  }
}
