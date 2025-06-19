//
//  IntegerView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 19.06.25.
//

import DataModel
import SwiftUI

struct IntegerView: View {
    @Binding var instance: CustomFieldInstance

    @State private var value: String = ""

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .integer(integer) = instance.wrappedValue.value {
            let val = integer.map { String($0) } ?? ""
            _value = State(initialValue: val)
        }
    }

    var body: some View {
        Section(instance.field.name) {
            TextField(instance.field.name, text: $value)
                .keyboardType(.numberPad)
        }
        .onChange(of: value) { old, new in
            guard value.count > 0 else {
                instance.value = .integer(nil)
                return
            }

            guard let val = Int(String(new)) else {
                value = old // Revert to old value if invalid
                return
            }

            instance.value = .integer(val)
        }
    }
}

private let field = CustomField(id: 1, name: "Custom int", dataType: .integer)

#Preview {
    @Previewable @State var instance = CustomFieldInstance(field: field, value: .integer(123))

    return Form {
        IntegerView(instance: $instance)

        Section("Instance") {
            Text(String(describing: instance))
        }
    }
}
