//
//  CorrespondentEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.02.26.
//

import DataModel
import Networking
import SwiftUI

struct CorrespondentEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController
  @Environment(\.dismiss) private var dismiss

  @State private var searchText = ""
  @State private var saving = false

  private var correspondents: [Correspondent] {
    let search = searchText.lowercased()
    return store.correspondents.values
      .filter { $0.id != viewModel.document.correspondent }
      .filter { search.isEmpty || $0.name.lowercased().contains(search) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private var selectedCorrespondent: Correspondent? {
    viewModel.document.correspondent.flatMap { store.correspondents[$0] }
  }

  private func select(correspondent: UInt?) {
    guard !saving else { return }
    guard viewModel.document.correspondent != correspondent else {
      dismiss()
      return
    }

    let previous = viewModel.document.correspondent
    viewModel.document.correspondent = correspondent

    Task {
      do {
        saving = true
        async let updatedDocument = store.updateDocument(viewModel.document)
        async let delay: () = Task.sleep(for: .seconds(0.3))

        let updated = try await updatedDocument
        try await delay
        viewModel.document = updated
        saving = false
        dismiss()
      } catch {
        viewModel.document.correspondent = previous
        saving = false
        errorController.push(error: error)
      }
    }
  }

  private func row(_ label: String, id: UInt?) -> some View {
    Button {
      select(correspondent: id)
    } label: {
      CustomSectionRow {
        HStack {
          Text(label)
            .foregroundStyle(.primary)
          Spacer()
          if viewModel.document.correspondent == id {
            Label(String(localized: .localizable(.elementIsSelected)), systemImage: "checkmark")
              .labelStyle(.iconOnly)
          }
        }
      }
    }
    .buttonStyle(.borderless)
    .disabled(saving)
  }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical) {
        VStack(spacing: 0) {
          CustomSection {
            if let selectedCorrespondent {
              Button {
                select(correspondent: nil)
              } label: {
                CustomSectionRow {
                  HStack {
                    Text(selectedCorrespondent.name)
                      .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "xmark.circle.fill")
                      .foregroundStyle(.secondary)
                  }
                }
              }
              .buttonStyle(.plain)
              .disabled(saving)
            } else {
              CustomSectionRow {
                Text(.localizable(.correspondentNotAssignedPicker))
                  .foregroundStyle(.secondary)
              }
            }
          } header: {
            Text(.localizable(.selected))
          }

          CustomSection {
            VStack(spacing: 0) {
              ForEach(Array(correspondents.enumerated()), id: \.element.id) { index, correspondent in
                row(correspondent.name, id: correspondent.id)

                if index < correspondents.count - 1 {
                  Divider()
                }
              }
            }
          } header: {
            Text(.localizable(.correspondents))
          }
        }
      }
      .customSectionBackground(.thickMaterial)
      .scrollBounceBehavior(.basedOnSize)
      .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
      .navigationTitle(.localizable(.correspondent))
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
