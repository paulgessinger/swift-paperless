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
  @Namespace private var correspondentNamespace

  private let animation = Animation.spring(duration: 0.2)
  private static let selectedRowTransition = AnyTransition.asymmetric(
    insertion: .move(edge: .bottom).combined(with: .opacity),
    removal: .move(edge: .bottom).combined(with: .opacity)
  )

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

  @ViewBuilder
  private func correspondentLabel(_ correspondent: Correspondent, selected: Bool) -> some View {
    HStack {
      Text(correspondent.name)
        .foregroundStyle(.primary)
      Spacer()
      if selected {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
    }
  }

  private func select(correspondent: UInt?) {
    guard !saving else { return }
    guard viewModel.document.correspondent != correspondent else {
      dismiss()
      return
    }

    let previous = viewModel.document.correspondent
    Haptics.shared.impact(style: .light)

    viewModel.document.correspondent = correspondent

    Task {
      do {
        saving = true
        async let updatedDocument = store.updateDocument(viewModel.document)
        async let delay: () = Task.sleep(for: .seconds(0.5))

        let updated = try await updatedDocument
        try await delay
        viewModel.document = updated
        saving = false
        if correspondent != nil {
          dismiss()
        }
      } catch {
        viewModel.document.correspondent = previous
        saving = false
        errorController.push(error: error)
      }
    }
  }

  private func row(_ correspondent: Correspondent) -> some View {
    Button {
      select(correspondent: correspondent.id)
    } label: {
      CustomSectionRow {
        correspondentLabel(correspondent, selected: false)
      }
    }
    .buttonStyle(.borderless)
    .allowsHitTesting(!saving)
    .id(correspondent.id)
    .transition(Self.selectedRowTransition)
  }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical) {
        VStack(spacing: 0) {
          CustomSection {
            VStack {

              if let selectedCorrespondent {
                Button {
                  select(correspondent: nil)
                } label: {
                  CustomSectionRow {
                    correspondentLabel(selectedCorrespondent, selected: true)
                  }
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!saving)
                .transition(Self.selectedRowTransition)
                .id(selectedCorrespondent.id)
              } else {
                CustomSectionRow {
                  Text(.localizable(.correspondentNotAssignedPicker))
                    .foregroundStyle(.secondary)
                }
                .transition(Self.selectedRowTransition)
              }
            }
            .animation(animation, value: viewModel.document.correspondent)
          } header: {
            Text(.localizable(.selected))
          }

          VStack(spacing: 0) {
            if !correspondents.isEmpty {
              CustomSection {
                VStack(spacing: 0) {
                  ForEach(Array(correspondents.enumerated()), id: \.element.id) {
                    index, correspondent in
                    row(correspondent)

                    if index < correspondents.count - 1 {
                      Divider()
                    }
                  }
                }
                .animation(animation, value: viewModel.document.correspondent)
              } header: {
                Text(.localizable(.correspondents))
              }
            }
          }
          .animation(animation, value: correspondents.isEmpty)
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
    .onAppear {
      Haptics.shared.prepare()
    }
  }
}
