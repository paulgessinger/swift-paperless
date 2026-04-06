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

  private var suggestedDates: [Date] {
    (viewModel.suggestions.dates).filter {
      !Calendar.current.isDate($0, inSameDayAs: date)
    }
  }

  init(viewModel: DocumentDetailModel) {
    self.viewModel = viewModel
    _date = State(initialValue: viewModel.document.created)
  }

  private func save() {
    Task {
      do {
        saving = true
        viewModel.document.created = date
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
              DatePicker(
                String(localized: .localizable(.documentEditCreatedDateLabel)),
                selection: $date,
                displayedComponents: .date
              )
            }
            
            if !suggestedDates.isEmpty {
              Divider()
              CustomSectionRow {
                HFlow {
                  ForEach(suggestedDates, id: \.self) { suggestedDate in
                    SuggestionPill(text: suggestedDate.formatted(date: .abbreviated, time: .omitted)) {
                      date = suggestedDate
                    }
                  }
                }
              }
            }
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
