//
//  SelectView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 15.06.25.
//

import DataModel
import SwiftUI

struct SelectView: View {
    @Binding var instance: CustomFieldInstance

    private let options: [CustomField.SelectOption]
    @State private var selected: CustomField.SelectOption? = nil

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .select(value) = instance.wrappedValue.value {
            options = instance.wrappedValue.field.extraData.selectOptions
            _selected = State(initialValue: value)
        } else {
            options = []
        }
    }

    var body: some View {
        Section {
            Picker(instance.field.name, selection: $selected) {
                Text("none")
                    .tag(nil as CustomField.SelectOption?)
                ForEach(options) { option in
                    Text(option.label)
                        .tag(option as CustomField.SelectOption?)
                }
            }
        }
        .onChange(of: selected) {
            instance.value = .select(selected)
        }
    }
}

private let field = CustomField(
    id: 10, name: "Custom select", dataType: .select,
    extraData: .init(selectOptions: [
        .init(id: "aa", label: "Option A"),
        .init(id: "bb", label: "Option B"),
        .init(id: "cc", label: "Option C"),
    ])
)

#Preview {
    @Previewable @State var instance = CustomFieldInstance(
        field: field, value: .select(.init(id: "bb", label: "Option B"))
    )!

    return Form {
        SelectView(instance: $instance)

        Section("Instance") {
            Text(String(describing: instance))
        }
    }
}
