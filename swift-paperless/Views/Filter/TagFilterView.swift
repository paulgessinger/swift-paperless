//
//  TagFilterView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 28.06.25.
//

import DataModel
import Foundation
import Networking
import SwiftUI
import os

struct TagFilterView: View {
  @EnvironmentObject private var store: DocumentStore

  @StateObject private var searchDebounce = DebounceObject(delay: 0.1)

  private enum Mode {
    case all
    case any
  }

  @Binding var selectedTags: FilterState.TagFilter
  @State private var mode = Mode.all

  init(selectedTags: Binding<FilterState.TagFilter>) {
    _selectedTags = selectedTags
    switch self.selectedTags {
    case .anyOf:
      _mode = State(initialValue: Mode.any)
    case .allOf:
      _mode = State(initialValue: Mode.all)
    default: break
    }
  }

  private func row(
    action: @escaping () -> Void,
    active: Bool,
    @ViewBuilder content: () -> some View
  ) -> some View {
    HStack {
      Button(action: { withAnimation { action() } }, label: content)
        .foregroundColor(.primary)
      Spacer()
      if active {
        Label(String(localized: .localizable(.tagIsSelected)), systemImage: "checkmark")
          .labelStyle(.iconOnly)
      }
    }
  }

  private func tagFilter(tag: Tag) -> Bool {
    if searchDebounce.debouncedText.isEmpty { return true }
    if tag.name.range(of: searchDebounce.debouncedText, options: .caseInsensitive) != nil {
      return true
    } else {
      return false
    }
  }

  private func onPress(tag: Tag) {
    var next: FilterState.TagFilter = selectedTags

    switch selectedTags {
    case .any:
      next = .allOf(include: [tag.id], exclude: [])

    case .notAssigned:
      next = .allOf(include: [tag.id], exclude: [])

    case .allOf(let include, let exclude):
      if include.contains(tag.id) {
        next = .allOf(
          include: include.filter { $0 != tag.id },
          exclude: exclude + [tag.id]
        )
      } else if exclude.contains(tag.id) {
        next = .allOf(
          include: include,
          exclude: exclude.filter { $0 != tag.id }
        )
      } else {
        next = .allOf(
          include: include + [tag.id],
          exclude: exclude
        )
      }

    case .anyOf(let ids):
      if ids.contains(tag.id) {
        next = .anyOf(ids: ids.filter { $0 != tag.id })
      } else {
        next = .anyOf(ids: ids + [tag.id])
      }
    }

    switch next {
    case .allOf(let include, let exclude):
      if include.isEmpty, exclude.isEmpty {
        next = .any
      }
      if !exclude.isEmpty {
        mode = .all
      }
    case .anyOf(let ids):
      if ids.isEmpty {
        next = .any
      }
    default:
      break
    }

    withAnimation {
      selectedTags = next
    }
  }

  private var sortedTags: [Tag] {
    store.tags.values.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  var body: some View {
    VStack {
      Form {
        Section {
          row(
            action: {
              Task { withAnimation { selectedTags = .any } }
            }, active: selectedTags == .any,
            content: {
              Text(.localizable(.tagsFilterAny))
            })

          row(
            action: {
              Task { withAnimation { selectedTags = .notAssigned } }
            }, active: selectedTags == .notAssigned,
            content: {
              Text(.localizable(.tagsNotAssignedPicker))
            })
        }

        Section {
          ForEach(
            sortedTags
              .filter { tagFilter(tag: $0) },
            id: \.id
          ) { tag in
            HStack {
              Button(action: { onPress(tag: tag) }) {
                TagView(tag: tag)
              }

              Spacer()

              VStack {
                let empty = Label(
                  String(localized: .localizable(.tagIsNotSelected)), systemImage: "circle"
                )
                .labelStyle(.iconOnly)
                switch selectedTags {
                case .any:
                  empty
                case .notAssigned:
                  empty
                case .allOf(let include, let exclude):
                  if include.contains(tag.id) {
                    Label(
                      String(localized: .localizable(.tagIncluded)), systemImage: "checkmark.circle"
                    )
                    .labelStyle(.iconOnly)
                  } else if exclude.contains(tag.id) {
                    Label(
                      String(localized: .localizable(.tagExcluded)), systemImage: "xmark.circle"
                    )
                    .labelStyle(.iconOnly)
                  } else {
                    empty
                  }
                case .anyOf(let ids):
                  if ids.contains(tag.id) {
                    Label(
                      String(localized: .localizable(.tagIsSelected)),
                      systemImage: "checkmark.circle"
                    )
                    .labelStyle(.iconOnly)
                  } else {
                    empty
                  }
                }
              }
              .frame(width: 20, alignment: .trailing)
            }
            .transaction { transaction in transaction.animation = nil }
          }
        } header: {
          Picker("Tag filter mode", selection: $mode) {
            Text(.localizable(.tagsAll)).tag(Mode.all)
            Text(.localizable(.tagsAny)).tag(Mode.any)
          }
          .textCase(.none)
          .padding(.bottom, 10)
          .pickerStyle(.segmented)
          .disabled(
            {
              switch selectedTags {
              case .any:
                true
              case .notAssigned:
                true
              case .allOf(_, let exclude):
                !exclude.isEmpty
              case .anyOf:
                false
              }
            }())
        }
      }

      .searchable(text: $searchDebounce.text, placement: .navigationBarDrawer(displayMode: .always))
    }

    .onChange(of: mode) { _, value in
      switch value {
      case .all:
        switch selectedTags {
        case .allOf:
          break  // already in all
        case .anyOf(let ids):
          selectedTags = .allOf(include: ids, exclude: [])
        default:
          Logger.shared.trace("Switched to Mode.all in invalid state\("")")
        }
      case .any:
        switch selectedTags {
        case .allOf(let include, let exclude):
          if !exclude.isEmpty {
            Logger.shared.trace("Switched to Mode.any, but had excludes??\("")")
          }
          selectedTags = .anyOf(ids: include)
        case .anyOf:
          break  // already in any
        default:
          Logger.shared.trace("Switched to Mode.any in invalid state\("")")
        }
      }
    }
  }
}

#Preview {
  @Previewable @StateObject var store = DocumentStore(repository: TransientRepository())

  @Previewable @State var filterState = FilterState.default

  NavigationStack {
    TagFilterView(selectedTags: $filterState.tags)
      .environmentObject(store)

      .toolbar {
        ToolbarItem {
          SaveButton {}
        }
      }
  }
}
