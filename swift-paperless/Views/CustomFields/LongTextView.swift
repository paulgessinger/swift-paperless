//
//  LongTextView.swift
//  swift-paperless
//
//  Created by AI Assistant for issue #367
//

import DataModel
import SwiftUI

struct LongTextView: View {
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
      Text(instance.field.name)
        .font(.footnote)
        .bold()

      TextEditor(text: $text)
        .frame(minHeight: 100)
        .scrollContentBackground(.hidden)
        .padding(4)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
    .onChange(of: text) {
      instance.value = .string(text)
    }
  }
}

private let field = CustomField(id: 1, name: "Custom long text", dataType: .longText)

#Preview {
  @Previewable @State var instance = CustomFieldInstance(field: field, value: .string(""))

  return Form {
    LongTextView(instance: $instance)

    Section("Instance") {
      Text(String(describing: instance))
    }
  }
}
