//
//  TagEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.04.23.
//

import Combine
import SwiftUI

struct TagEditView<Element>: View where Element: TagProtocol & Sendable {
    var onSave: (Element) throws -> Void

//    @Environment(\.dismiss) private var dismiss

    var saveLabel: String

    @StateObject private var tag: ThrottleObject<Element>

    init(tag: Element,
         onSave: @escaping (Element) throws -> Void = { _ in })
    {
        _tag = StateObject(wrappedValue: ThrottleObject(value: tag, delay: 0.5))
        self.onSave = onSave
        saveLabel = String(localized: .localizable.save)
    }

    private let scale = 2.0

    private static func randomColor() -> Color {
        .init(red: Double.random(in: 0 ... 1),
              green: Double.random(in: 0 ... 1),
              blue: Double.random(in: 0 ... 1))
    }

    private func valid() -> Bool {
        !tag.value.name.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: .localizable.tagName), text: $tag.value.name)
                    .clearable($tag.value.name)

                Toggle(String(localized: .localizable.tagIsInbox), isOn: $tag.value.isInboxTag)
            } header: {
                Text(!tag.throttledValue.name.isEmpty ? tag.throttledValue.name : String(localized: .localizable.tagName))

                    .lineLimit(1)
                    .truncationMode(.middle)

                    .font(.title3)
                    .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .background(tag.value.color.color)
                    .foregroundColor(tag.value.textColor.color)
                    .clipShape(Capsule())
                    .textCase(.none)
                    .animation(.linear(duration: 0.2), value: tag.throttledValue.name)

                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Section(String(localized: .localizable.color)) {
                ColorPicker(String(localized: .localizable.color),
                            selection: $tag.value.color.color,
                            supportsOpacity: false)
                Button {
                    withAnimation {
                        tag.value.color.color = Self.randomColor()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text(.localizable.tagColorRandom)
                        Spacer()
                    }
                }
            }

            MatchEditView(element: $tag.value)
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(saveLabel) {
                    do {
                        try onSave(tag.value)
//                        dismiss()
                    } catch {
                        print("Save tag error: \(error)")
                    }
                }
                .disabled(!valid())
                .bold()
            }
        }

        .navigationTitle(Element.self is Tag.Type ? Text(.localizable.tagEditTitle) : Text(.localizable.tagCreateTitle))
    }
}

extension TagEditView where Element == ProtoTag {
    @MainActor
    init(onSave: @escaping (Element) throws -> Void = { _ in }) {
        self.init(tag: ProtoTag(color: HexColor(Self.randomColor())),
                  onSave: onSave)
        saveLabel = String(localized: .localizable.add)
    }
}

struct TagEditView_Previews: PreviewProvider {
    struct Container: View {
        var body: some View {
            NavigationStack {
                TagEditView<ProtoTag>()
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle(Text(.localizable.tagCreateTitle))
            }
        }
    }

    static var previews: some View {
        Container()
    }
}
