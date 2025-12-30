//
//  TagEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.04.23.
//

import Combine
import Common
import DataModel
import SwiftUI
import os

struct TagEditView<Element>: View where Element: TagProtocol & Sendable {
  var onSave: ((Element) throws -> Void)?

  //    @Environment(\.dismiss) private var dismiss

  var saveLabel: String

  @State private var tag: Element

  let editable: Bool

  init(
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

  var body: some View {
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
          .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
          .background(tag.color.color)
          .foregroundColor(tag.textColor.color)
          .clipShape(Capsule())
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
  init(onSave: @escaping (Element) throws -> Void) {
    self.init(
      element: ProtoTag(color: HexColor(Self.randomColor())),
      onSave: onSave)
    saveLabel = String(localized: .localizable(.add))
  }
}

#Preview {
  NavigationStack {
    TagEditView<ProtoTag>(onSave: { _ in })
      .navigationBarTitleDisplayMode(.inline)
      .navigationTitle(Text(.localizable(.tagCreateTitle)))
  }
}
