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
        if case let .string(string) = instance.wrappedValue.value {
            _text = State(initialValue: string)
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(instance.field.name)
                .font(.footnote)
                .bold()

            TextField(instance.field.name, text: $text)
        }
        .onChange(of: text) {
            instance.value = .string(text)
        }
    }
}

private let field = CustomField(id: 1, name: "Custom string", dataType: .string)

#Preview {
    @Previewable @State var instance = CustomFieldInstance(field: field, value: .string("Blubb"))

    return Form {
        StringView(instance: $instance)

        Section("Instance") {
            Text(String(describing: instance))
        }
    }
}
