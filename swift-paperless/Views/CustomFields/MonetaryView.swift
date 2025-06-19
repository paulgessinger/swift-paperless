//
//  MonetaryView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 19.06.25.
//

import DataModel
import SwiftUI

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

                TextField(.customFields(.monetaryAmountPlaceholder), text: $amountString)
                    .keyboardType(.decimalPad)
            }
        }
        .onChange(of: amountString) { old, new in
            guard amountString.count > 0 else {
                amountString = "1"
                instance.value = .monetary(currency: currency, amount: 1)
                return
            }

            // @FIXME: This lets through characters in the string, not sure if this is a problem
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

private let field = CustomField(id: 1, name: "Custom monetary", dataType: .monetary)

#Preview {
    @Previewable @State var instance = CustomFieldInstance(field: field, value: .monetary(currency: "EUR", amount: 1234.56))

    return Form {
        MonetaryView(instance: $instance)

        Section("Instance") {
            Text(String(describing: instance))
        }
    }
}
