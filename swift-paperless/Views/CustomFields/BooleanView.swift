//
//  BooleanView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 19.06.25.
//

import DataModel
import SwiftUI

struct BooleanView: View {
    @Binding var instance: CustomFieldInstance

    @State private var value: Bool = false

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .boolean(bool) = instance.wrappedValue.value {
            _value = State(initialValue: bool)
        }
    }

    var body: some View {
        Toggle(isOn: $value) {
            Text(instance.field.name)
        }
        .onChange(of: value) { _, new in
            instance.value = .boolean(new)
        }
    }
}

private let field = CustomField(id: 1, name: "Custom bool", dataType: .boolean)

#Preview {
    @Previewable @State var instance = CustomFieldInstance(field: field, value: .boolean(true))

    return Form {
        BooleanView(instance: $instance)

        Section("Instance") {
            Text(String(describing: instance))
        }
    }
}
