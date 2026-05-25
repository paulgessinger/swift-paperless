//
//  TitleEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 01.04.26.
//

import AppShared
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

  // Paperless-ngx rejects titles longer than this; clamp at the source so
  // the user gets immediate feedback rather than a save-time error.
  private static let titleCharacterLimit = 128

  private func save() {
    Task {
      let origTitle = viewModel.document.title
      do {
        saving = true
        viewModel.document.title = title.trimmingCharacters(in: .whitespaces)
        try await viewModel.updateDocument()
        Haptics.shared.notification(.success)
        saving = false
        dismiss()
      } catch {
        saving = false
        viewModel.document.title = origTitle
        errorController.push(error: error)
      }
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical) {
        CustomSection {
          CustomSectionRow {
            VStack(alignment: .leading, spacing: 6) {
              TextField(
                String(localized: .localizable(.documentEditTitleLabel)),
                text: $title,
                axis: .vertical
              )
              .focused($focused)
              .onChange(of: title) { _, newValue in
                // Server-side limit; truncate inline so the user sees the
                // cap rather than getting an error on save.
                if newValue.count > Self.titleCharacterLimit {
                  title = String(newValue.prefix(Self.titleCharacterLimit))
                }
              }

              Text("\(title.count) / \(Self.titleCharacterLimit)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(
                  title.count >= Self.titleCharacterLimit ? .secondary : .tertiary
                )
            }
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
