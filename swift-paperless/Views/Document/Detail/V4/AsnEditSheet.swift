//
//  AsnEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.04.26.
//

import DataModel
import Networking
import SwiftUI

struct AsnEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController
  @Environment(\.dismiss) private var dismiss

  @State private var asnText: String
  @State private var saving = false
  @State private var nextAsn: UInt?

  init(viewModel: DocumentDetailModel) {
    self.viewModel = viewModel
    _asnText = State(initialValue: viewModel.document.asn.map { String($0) } ?? "")
  }

  private var parsedAsn: UInt? {
    UInt(asnText)
  }

  private var hasChanges: Bool {
    parsedAsn != viewModel.document.asn
  }

  private var isValid: Bool {
    asnText.isEmpty || parsedAsn != nil
  }

  private func loadNextAsn() async {
    do {
      nextAsn = try await store.repository.nextAsn()
    } catch {
      errorController.push(error: error)
    }
  }

  private func save() {
    Task {
      do {
        saving = true
        viewModel.document.asn = parsedAsn
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
      ScrollView(.vertical) {
        CustomSection {
          VStack(alignment: .leading, spacing: 0) {
            CustomSectionRow {
              HStack {
                Text(.localizable(.asn))
                Spacer()
                TextField(
                  "#",
                  text: $asnText
                )
                .clearable($asnText)
                .keyboardType(.numberPad)
              }
            }

            if asnText.isEmpty, let nextAsn {
              SuggestionsRow {
                SuggestionPill(text: String(localized: .localizable(.asnNext(nextAsn)))) {
                  withAnimation(.spring(duration: 0.2)) {
                    asnText = String(nextAsn)
                  }
                }
              }
            }
          }
          .animation(.spring(duration: 0.2), value: asnText.isEmpty)
        }
      }
      .customSectionBackground(.thickMaterial)
      .scrollBounceBehavior(.basedOnSize)
      .navigationTitle(.localizable(.asn))
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
            .disabled(!hasChanges || !isValid)
          }
        }
      }
    }
    .interactiveDismissDisabled(saving || hasChanges)
    .task {
      await loadNextAsn()
    }
  }
}
