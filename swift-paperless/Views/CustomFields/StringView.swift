//
//  StringView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 19.06.25.
//

import DataModel
import SwiftUI

struct StringView: View {
  @Binding var instance: CustomFieldInstance

  @State private var text: String = ""

  init(instance: Binding<CustomFieldInstance>) {
    _instance = instance
    if case .string(let string) = instance.wrappedValue.value {
      _text = State(initialValue: string)
    }
  }

  var body: some View {
    VStack(alignment: .leading) {
      if !text.isEmpty {
        Text(instance.field.name)
          .font(.footnote)
          .bold()
          .transition(.opacity.combined(with: .move(edge: .bottom)))
      }

      TextField(instance.field.name, text: $text)
    }
    .animation(.spring(), value: text)
    .onChange(of: text) {
      instance.value = .string(text)
    }
  }
}

private let field = CustomField(id: 1, name: "Custom string", dataType: .string)

#Preview {
  @Previewable @State var instance = CustomFieldInstance(field: field, value: .string(""))

  return Form {
    StringView(instance: $instance)

    Section("Instance") {
      Text(String(describing: instance))
    }
  }
}
