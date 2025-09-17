//
//  FloatView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.06.25.
//

import DataModel
import SwiftUI

struct FloatView: View {
  @Binding var instance: CustomFieldInstance

  @State private var value: String = ""

  init(instance: Binding<CustomFieldInstance>) {
    _instance = instance
    if case .float(let float) = instance.wrappedValue.value {
      let val = float.map { String($0) } ?? ""
      _value = State(initialValue: val)
    }
  }

  var body: some View {
    HStack {
      Text(instance.field.name)
        .frame(maxWidth: .infinity, alignment: .leading)

      TextField(instance.field.name, text: $value)
        .keyboardType(.decimalPad)
    }
    .onChange(of: value) { old, new in
      guard value.count > 0 else {
        instance.value = .float(nil)
        return
      }

      guard let val = Double(String(new)) else {
        value = old  // Revert to old value if invalid
        return
      }

      instance.value = .float(val)
    }
  }
}

private let field = CustomField(id: 1, name: "Custom float", dataType: .float)

#Preview {
  @Previewable @State var instance = CustomFieldInstance(field: field, value: .float(123.45))

  return Form {
    FloatView(instance: $instance)

    Section("Instance") {
      Text(String(describing: instance))
    }
  }
}
