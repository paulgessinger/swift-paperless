//
//  CustomFieldValueViews.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 15.06.25.
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
        Section(instance.field.name) {
            TextField(instance.field.name, text: $text)
        }
        .onChange(of: text) {
            instance.value = .string(text)
        }
    }
}

struct FloatView: View {
    @Binding var instance: CustomFieldInstance

    @State private var value: String = ""

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .float(float) = instance.wrappedValue.value {
            _value = State(initialValue: String(float))
        }
    }

    var body: some View {
        Section(instance.field.name) {
            TextField(instance.field.name, text: $value)
                .keyboardType(.decimalPad)
        }
        .onChange(of: value) { old, new in
            guard let val = Double(String(new)) else {
                value = old // Revert to old value if invalid
                return
            }
            instance.value = .float(val)
        }
    }
}

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

struct IntegerView: View {
    @Binding var instance: CustomFieldInstance

    @State private var value: String = ""

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .integer(integer) = instance.wrappedValue.value {
            _value = State(initialValue: String(integer))
        }
    }

    var body: some View {
        Section(instance.field.name) {
            TextField(instance.field.name, text: $value)
                .keyboardType(.numberPad)
        }
        .onChange(of: value) { old, new in
            guard let val = Int(String(new)) else {
                value = old // Revert to old value if invalid
                return
            }
            instance.value = .integer(val)
        }
    }
}

struct DateView: View {
    @Binding var instance: CustomFieldInstance

    @State private var value: Date = .init()

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .date(date) = instance.wrappedValue.value {
            _value = State(initialValue: date)
        }
    }

    var body: some View {
        DatePicker(selection: $value, displayedComponents: .date) {
            Text(instance.field.name)
        }
        .onChange(of: value) { _, new in
            instance.value = .date(new)
        }
    }
}

struct MonetaryView: View {
    @Binding var instance: CustomFieldInstance

    @State private var amount: Decimal = 0.0
    @State private var amountString: String = ""

    @State private var currency: String = ""

    @Environment(\.locale) private var locale

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
    }

    private var defaultCurrency: String {
        instance.field.extraData.defaultCurrency ?? Locale.current.currency?.identifier ?? ""
    }

    var body: some View {
        Section(instance.field.name) {
            HStack {
                if case let .monetary(currency, amount) = instance.value {
                    Text(amount, format: .currency(code: currency))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.default, value: instance.value)
                        .contentTransition(.numericText())
                }

                TextField(defaultCurrency, text: $currency)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .fixedSize()

                TextField("Amount", text: $amountString)
                    .keyboardType(.decimalPad)
            }
        }
        .onChange(of: amountString) { old, new in
            guard let val = Decimal(string: new, locale: locale) else {
                amountString = old // Revert to old value if invalid
                return
            }
            amount = val
            instance.value = .monetary(currency: currency, amount: val)
        }

        .onChange(of: currency) { old, new in
            // check if is valid currency code
            let ex = /^[A-Z]*$/
            if new.wholeMatch(of: ex) == nil {
                currency = old // Revert to old value if invalid
                return
            }

            currency = new

            var setCurrency = new
            if setCurrency.isEmpty {
                setCurrency = defaultCurrency
            }

            if new.count == 0 || new.count == 3 {
                instance.value = .monetary(currency: setCurrency, amount: amount)
            }
        }

        .task {
            if case let .monetary(currency, amount) = instance.value {
                self.amount = amount
                amountString = amount.formatted(.number.locale(
                    locale
                )
                .grouping(.never)
                .decimalSeparator(strategy: .always)
                .precision(.fractionLength(2)))
                self.currency = currency
            }
        }
    }
}

struct UrlView: View {
    @Binding var instance: CustomFieldInstance

    @State private var url: String = ""

    @Environment(\.openURL) private var openURL

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .url(u) = instance.wrappedValue.value {
            _url = State(initialValue: u?.absoluteString ?? "")
        }
    }

    private func valid(urlString: String) -> URL? {
        guard let u = URL(string: urlString), u.scheme != nil, u.host != nil else {
            return nil
        }
        return u
    }

    var body: some View {
        Section(instance.field.name) {
            HStack {
                TextField(instance.field.name, text: $url)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                let validUrl = valid(urlString: url)
                let isValid = validUrl != nil
                HStack {
                    Text(isValid ? .customFields(.urlFieldOpenLabel) : .customFields(.urlFieldInvalidLabel))
                    Image(systemName: isValid ? "arrow.up.right.circle.fill" : "xmark.circle.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(isValid ? Color.accentColor : Color.red)
                .if(isValid) { view in
                    view.onTapGesture {
                        if let validUrl {
                            openURL(validUrl)
                        }
                    }
                }
            }
        }
        .animation(.spring, value: url)

        .onChange(of: url) { _, new in
            guard !new.isEmpty else {
                instance.value = .url(nil)
                return
            }

            guard let url = URL(string: new) else {
                return
            }

            instance.value = .url(url)
        }
    }
}
