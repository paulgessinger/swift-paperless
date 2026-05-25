//
//  TagEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.04.23.
//

import Combine
import Common
import DataModel
import Networking
import SwiftUI
import os

public struct TagEditView<Element>: View where Element: TagProtocol & Sendable {
  @EnvironmentObject private var store: DocumentStore
  @Environment(\.colorScheme) private var colorScheme

  public var onSave: ((Element) throws -> Void)?

  //    @Environment(\.dismiss) private var dismiss

  public var saveLabel: String

  @State private var tag: Element

  public let editable: Bool

  /// Persisted id of the tag being edited, when applicable. `nil` when creating
  /// (`ProtoTag`); used to exclude self + descendants from the parent picker.
  private var persistedId: UInt? {
    (tag as? Tag)?.id
  }

  public init(
    element: Element,
    onSave: ((Element) throws -> Void)?
  ) {
    _tag = State(initialValue: element)
    self.onSave = onSave
    editable = onSave != nil
    saveLabel = String(localized: .localizable(.save))
  }

  private let scale = 2.0

  private static func randomColor() -> Color {
    .init(
      red: Double.random(in: 0...1),
      green: Double.random(in: 0...1),
      blue: Double.random(in: 0...1))
  }

  private func valid() -> Bool {
    !tag.name.isEmpty && editable
  }

  @ViewBuilder
  private var parentLabel: some View {
    if let id = tag.parent, let parent = store.tags[id] {
      TagView(tag: parent)
    } else {
      Text(.localizable(.none))
    }
  }

  public var body: some View {
    Form {
      Section {
        TextField(String(localized: .localizable(.tagName)), text: $tag.name)
          .clearable($tag.name)
          .disabled(!editable)

        Toggle(String(localized: .localizable(.tagIsInbox)), isOn: $tag.isInboxTag)
          .disabled(!editable)
      } header: {
        Text(!tag.name.isEmpty ? tag.name : String(localized: .localizable(.tagName)))
          .lineLimit(1)
          .truncationMode(.middle)
          .font(.title3)
          .padding(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
          .background(tag.color.color.opacity(0.28))
          .foregroundColor(
            blend(colorScheme == .dark ? .white : .black, tag.color.color, by: 0.35)
          )
          .clipShape(Capsule())
          .overlay {
            Capsule()
              .strokeBorder(tag.color.color, lineWidth: 1)
          }
          .textCase(.none)
          .animation(.linear(duration: 0.2), value: tag.name)
          .frame(maxWidth: .infinity, alignment: .center)
      }

      Section(String(localized: .localizable(.color))) {
        ColorPicker(
          String(localized: .localizable(.color)),
          selection: $tag.color.color,
          supportsOpacity: false
        )
        .disabled(!editable)
        Button {
          withAnimation {
            tag.color.color = Self.randomColor()
          }
        } label: {
          HStack {
            Spacer()
            Text(.localizable(.tagColorRandom))
            Spacer()
          }
        }
        .disabled(!editable)
      }

      Section {
        NavigationLink {
          TagParentPickerView(selection: $tag.parent, excludingId: persistedId)
        } label: {
          HStack {
            Text(.localizable(.tagParent))
            Spacer()
            parentLabel
              .foregroundStyle(.secondary)
          }
        }
        .disabled(!editable)
      }

      MatchEditView(element: $tag)
        .disabled(!editable)
    }

    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        SaveButton(saveLabel) {
          do {
            try onSave?(tag)
          } catch {
            Logger.shared.error("Save tag error: \(error)")
          }
        }
        .disabled(!valid())
      }
    }

    .scrollBounceBehavior(.basedOnSize)
  }
}

extension TagEditView where Element == ProtoTag {
  @MainActor
  public init(onSave: @escaping (Element) throws -> Void) {
    self.init(
      element: ProtoTag(color: HexColor(Self.randomColor())),
      onSave: onSave)
    saveLabel = String(localized: .localizable(.add))
  }
}

// MARK: - Parent picker

public struct TagParentPickerView: View {
  @EnvironmentObject private var store: DocumentStore
  @Environment(\.dismiss) private var dismiss

  @Binding public var selection: UInt?
  /// Tag id to hide from the candidates along with all its descendants, to
  /// prevent self-parenting and cycles. `nil` when creating a new tag.
  public let excludingId: UInt?

  @State private var searchText = ""

  /// Returns `excludingId` and all of its transitive descendants.
  private func excludedSet() -> Set<UInt> {
    guard let excludingId else { return [] }
    var excluded: Set<UInt> = [excludingId]
    var changed = true
    let tags = store.tags
    while changed {
      changed = false
      for tag in tags.values {
        if let parent = tag.parent, excluded.contains(parent), !excluded.contains(tag.id) {
          excluded.insert(tag.id)
          changed = true
        }
      }
    }
    return excluded
  }

  private var candidates: [Tag] {
    let excluded = excludedSet()
    return store.tags.values
      .filter { !excluded.contains($0.id) }
      .filter {
        searchText.isEmpty
          || $0.name.range(of: searchText, options: .caseInsensitive) != nil
      }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func select(_ id: UInt?) {
    selection = id
    dismiss()
  }

  public var body: some View {
    List {
      Section {
        Button {
          select(nil)
        } label: {
          HStack {
            Text(.localizable(.none))
              .foregroundStyle(.primary)
            Spacer()
            if selection == nil {
              Image(systemName: "checkmark")
            }
          }
        }
      }

      Section {
        ForEach(candidates, id: \.id) { tag in
          Button {
            select(tag.id)
          } label: {
            HStack {
              TagView(tag: tag)
              Spacer()
              if selection == tag.id {
                Image(systemName: "checkmark")
              }
            }
          }
          .foregroundStyle(.primary)
        }
      }
    }
    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    .navigationTitle(Text(.localizable(.tagParent)))
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    TagEditView<ProtoTag>(onSave: { _ in })
      .navigationBarTitleDisplayMode(.inline)
      .navigationTitle(Text(.localizable(.tagCreateTitle)))
  }
}
