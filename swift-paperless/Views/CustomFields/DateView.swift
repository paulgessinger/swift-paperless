//
//  DateView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.06.25.
//

import DataModel
import SwiftUI

struct DateView: View {
    @Binding var instance: CustomFieldInstance

    @State private var value: Date = .now
    @State private var hasValue: Bool = false

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .date(date) = instance.wrappedValue.value {
            if let date {
                _value = State(initialValue: date)
                _hasValue = State(initialValue: true)
            }
        }
    }

    private func clear() {
        value = .now
        hasValue = false
    }

    var body: some View {
        Section {
            if hasValue {
                DatePicker(selection: $value, displayedComponents: .date) {
                    HStack {
                        Text(instance.field.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .accessibilityLabel(String(localized: .customFields(.dateClear)))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                clear()
                            }
                    }
                }
            } else {
                HStack {
                    Text(instance.field.name)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(.customFields(.dateAdd))
                    }
                    .foregroundColor(.accentColor)
                    .onTapGesture {
                        hasValue = true
                    }
                    .contentShape(Rectangle())
                }
            }
        } footer: {
            if !hasValue {
                Text(.customFields(.noDateDescription))
            }
        }
        .onChange(of: value) {
            if hasValue {
                guard let val = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: value) else {
                    return
                }
                instance.value = .date(val)
            } else {
                instance.value = .date(nil)
            }
        }
        .onChange(of: hasValue) {
            if hasValue {
                guard let val = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: value) else {
                    return
                }
                instance.value = .date(val)
            }
        }
    }
}

private let field = CustomField(id: 1, name: "Custom date", dataType: .date)

#Preview {
    @Previewable @State var instance = CustomFieldInstance(field: field, value: .date(.now))

    return Form {
        DateView(instance: $instance)

        Section("Instance") {
            Text(String(describing: instance))
            Text(String(describing: instance.value.rawValue))
        }
    }
}
